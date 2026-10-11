-- ============================================================
-- BOS tool · Phase 10 (plan B2 + B3 + B4-light): STOCK LEDGER, purchases and supplier ledger, batches / expiry.
-- Run AFTER phase8 and phase9 (it needs: rules, grants, emergency helpers rule_ok / use_emergency, lock_check, can_loc, log_change,
-- suppliers, unit_conversions / unit_factor, shelf_life_for, items.tracked / min_stock / base_unit, exceptions, option_lists).
-- ADDITIVE and IDEMPOTENT: safe to run again. Nothing existing is dropped or changed except that two triggers are ADDED on public.sales.
--
-- Principles kept
--   * Stock is counted only for items the owner marked tracked (items.tracked). With no tracked item this file changes NOTHING in the POS.
--   * The ledger is APPEND-ONLY (update / delete / truncate are blocked by triggers); a mistake is fixed by a reversing row, like a void.
--   * stock_balance is only a cache, written by a trigger on the ledger under a row lock; stock_reconcile() proves it equals the ledger.
--   * COST IS SECRET: unit_cost / avg_cost / values are not granted on the tables to the app roles. They are shown only by the functions,
--     and only to the owner, ITEM_COST holders or a holder of the grant view_cost (for that location).
--   * No business number is invented: every limit is a rule that is empty (= off) until the owner writes it; new emergency switches are off.
--   * Offline POS: a sale that syncs late still posts its stock (made_at = the sale time). With stock_negative_mode = warn / allow it never blocks.
-- ============================================================

-- ---------- (a) settings: rules, grants, lists ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('wastage_photo_above', 'stock', 'number', null, null, null, 0, 1000000000, 'এর বেশি পরিমাণ নষ্ট হলে ছবি লাগবে (বেস এককে)', 'এর বেশি quantity নষ্ট হলে photo লাগবে (base unit এ)', 'A photo is required for a wastage above this quantity (in the item base unit)', 'Empty = off. Quantity, not money, so that cost stays secret', 100),
 ('count_tolerance_pct', 'stock', 'number', null, '%', null, 0, 1000, 'গণনায় পার্থক্য এর বেশি হলে মালিককে জানানো (%)', 'Count এ পার্থক্য এর বেশি হলে মালিককে জানানো (%)', 'Tell the owner when a stock count differs by more than this %', 'Empty = off', 101),
 ('purchase_cost_jump_pct', 'purchase', 'number', null, '%', null, 0, 1000, 'আগের কেনার দামের চেয়ে এত % বেশি/কম হলে মালিককে জানানো', 'আগের কেনার দামের চেয়ে এত % বেশি/কম হলে মালিককে জানানো', 'Tell the owner when a unit cost differs from the last purchase by more than this %', 'Empty = off', 110),
 ('purchase_separate_poster', 'purchase', 'switch', 'false', null, null, null, null, 'যে বিল লিখেছে সে নিজে পোস্ট করতে পারবে না', 'যে bill লিখেছে সে নিজে post করতে পারবে না', 'The person who wrote a purchase bill cannot post it (the owner still can)', 'Off by default', 111),
 ('em_sell_below_zero', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: স্টকের চেয়ে বেশি বিক্রি', 'জরুরি request চলবে: stock এর চেয়ে বেশি বিক্রি', 'Emergency allowed for: selling more than the stock', 'Off by default', 120),
 ('em_stock_opening', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: প্রারম্ভিক স্টক', 'জরুরি request চলবে: opening stock', 'Emergency allowed for: opening stock', 'Off by default', 121),
 ('em_wastage', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: নষ্ট মাল বাদ দেওয়া', 'জরুরি request চলবে: wastage write-off', 'Emergency allowed for: wastage write-off', 'Off by default', 122),
 ('em_purchase_entry', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: ক্রয় এন্ট্রি', 'জরুরি request চলবে: purchase entry', 'Emergency allowed for: purchase entry', 'Off by default', 123),
 ('em_purchase_return', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: ক্রয় ফেরত', 'জরুরি request চলবে: purchase return', 'Emergency allowed for: purchase return', 'Off by default', 124),
 ('em_supplier_pay', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: সাপ্লায়ারকে পেমেন্ট', 'জরুরি request চলবে: supplier payment', 'Emergency allowed for: paying a supplier', 'Off by default', 125),
 ('em_purchase_void', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: ক্রয় বাতিল', 'জরুরি request চলবে: purchase void', 'Emergency allowed for: voiding a purchase', 'Off by default', 126)
on conflict (key) do nothing;

-- new grants. Role grants are seeded ONLY the first time a grant is created (an owner who removes one is not overruled by a re-run).
with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('sell_below_zero', 'stock', 40, 'স্টকের চেয়ে বেশি বিক্রি', 'Stock এর চেয়ে বেশি বিক্রি', 'Sell more than the stock', 'once', 'em_sell_below_zero'),
   ('stock_opening', 'stock', 41, 'প্রারম্ভিক স্টক বসানো', 'Opening stock বসানো', 'Enter opening stock', 'once', 'em_stock_opening'),
   ('wastage_write_off', 'stock', 42, 'নষ্ট / অপচয় মাল বাদ দেওয়া', 'নষ্ট / wastage মাল বাদ দেওয়া', 'Write off wasted stock', 'once', 'em_wastage'),
   ('stock_count_adjust', 'stock', 43, 'গণনা অনুযায়ী স্টক ঠিক করা', 'Count অনুযায়ী stock ঠিক করা', 'Adjust stock to a count', 'once', null),
   ('stock_transfer', 'stock', 44, 'এক জায়গা থেকে অন্য জায়গায় মাল পাঠানো / গ্রহণ', 'এক জায়গা থেকে অন্য জায়গায় মাল পাঠানো / receive', 'Send / receive stock between locations', 'once', null),
   ('stock_issue', 'stock', 45, 'উৎপাদনে কাঁচামাল দেওয়া', 'Production এ কাঁচামাল issue', 'Issue material to production', 'once', null),
   ('stock_production', 'stock', 46, 'উৎপাদিত মাল স্টকে তোলা', 'Production এর মাল stock এ তোলা', 'Post production into stock', 'once', null),
   ('purchase_entry', 'purchase', 50, 'ক্রয় বিল লেখা ও পোস্ট করা', 'Purchase bill লেখা ও post করা', 'Write and post purchase bills', 'once', 'em_purchase_entry'),
   ('purchase_return', 'purchase', 51, 'সাপ্লায়ারকে মাল ফেরত', 'Supplier কে মাল ফেরত', 'Return goods to a supplier', 'once', 'em_purchase_return'),
   ('supplier_pay', 'purchase', 52, 'সাপ্লায়ারকে টাকা দেওয়া', 'Supplier কে টাকা দেওয়া', 'Pay a supplier', 'once', 'em_supplier_pay'),
   ('purchase_void', 'purchase', 53, 'ক্রয় বিল / সাপ্লায়ার পেমেন্ট বাতিল', 'Purchase bill / supplier payment বাতিল', 'Void a purchase or a supplier payment', 'once', 'em_purchase_void')
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values
    ('wastage_write_off', 'storekeeper'), ('wastage_write_off', 'showroom_manager'), ('wastage_write_off', 'factory_incharge'), ('wastage_write_off', 'management'),
    ('stock_count_adjust', 'management'),
    ('stock_transfer', 'storekeeper'), ('stock_transfer', 'showroom_manager'), ('stock_transfer', 'factory_incharge'),
    ('stock_issue', 'storekeeper'), ('stock_issue', 'factory_incharge'),
    ('stock_production', 'factory_incharge'),
    ('purchase_entry', 'purchasing'), ('purchase_entry', 'storekeeper')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
  on conflict do nothing;

insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort) values
 ('wastage_reasons', 'expired', 'মেয়াদ শেষ', 'মেয়াদ শেষ', 'Expired', 1), ('wastage_reasons', 'spoiled', 'নষ্ট / পচে গেছে', 'নষ্ট / spoiled', 'Spoiled', 2),
 ('wastage_reasons', 'burnt', 'পুড়ে গেছে', 'পুড়ে গেছে', 'Burnt', 3), ('wastage_reasons', 'broken', 'ভেঙে গেছে', 'ভেঙে গেছে', 'Broken', 4),
 ('wastage_reasons', 'sample', 'নমুনা / বিনামূল্যে', 'Sample / free', 'Sample / free', 5), ('wastage_reasons', 'staff_meal', 'স্টাফ খাবার', 'Staff meal', 'Staff meal', 6),
 ('wastage_reasons', 'unknown', 'কারণ অজানা', 'কারণ unknown', 'Unknown reason', 9),
 ('return_reasons', 'damaged', 'ক্ষতিগ্রস্ত', 'Damaged', 'Damaged', 1), ('return_reasons', 'wrong_item', 'ভুল মাল', 'ভুল item', 'Wrong item', 2),
 ('return_reasons', 'quality', 'মান ভালো না', 'Quality ভালো না', 'Poor quality', 3), ('return_reasons', 'excess', 'বেশি এসেছে', 'বেশি এসেছে', 'Excess delivered', 4),
 ('return_reasons', 'other', 'অন্যান্য', 'Other', 'Other', 9)
on conflict (list_code, value_code) do nothing;

-- ---------- (b) tables ----------
-- the ledger: one row per movement, in the item BASE unit. Never changed after it is written.
create table if not exists public.stock_batches (
  id bigserial primary key,
  item_id uuid not null references public.items(id),
  location_id int not null references public.locations(id),
  made_at timestamptz not null,
  qty_made numeric not null check (qty_made > 0),
  qty_remaining numeric not null check (qty_remaining >= 0),
  expires_at timestamptz,                                  -- null = no shelf-life rule: expiry features are off for this batch
  shelf_rule jsonb,                                        -- the shelf_life_for() answer used (season / scope), for the record
  note text,
  created_by uuid, created_at timestamptz not null default now()
);
create index if not exists stock_batches_open on public.stock_batches (item_id, location_id, expires_at) where qty_remaining > 0;
create index if not exists stock_batches_exp on public.stock_batches (location_id, expires_at) where qty_remaining > 0 and expires_at is not null;

create table if not exists public.stock_ledger (
  id bigserial primary key,
  item_id uuid not null references public.items(id),
  location_id int not null references public.locations(id),
  qty_delta numeric not null check (qty_delta <> 0 and qty_delta <> 'NaN'::numeric),     -- in the item base unit; + in, - out
  unit_cost numeric check (unit_cost is null or unit_cost >= 0),                          -- per base unit. SECRET: not granted to the app roles
  reason text not null check (reason in ('opening', 'purchase_in', 'purchase_return', 'sale_out', 'sale_void_in', 'sale_return', 'issue_out',
                                         'production_in', 'transfer_out', 'transfer_in', 'wastage', 'count_adjust', 'reversal')),
  ref_type text, ref_id text,
  batch_id bigint references public.stock_batches(id),
  reverses_id bigint references public.stock_ledger(id),   -- set on a row that undoes another
  client_id uuid,                                          -- makes a re-sent phone request harmless
  made_at timestamptz not null default now(),              -- when it happened in the business (a late-synced sale keeps its sale time)
  note text,
  created_by uuid, created_at timestamptz not null default now()
);
create index if not exists stock_ledger_pair on public.stock_ledger (item_id, location_id, id);
create index if not exists stock_ledger_ref on public.stock_ledger (ref_type, ref_id);
create index if not exists stock_ledger_loc_time on public.stock_ledger (location_id, made_at);
create unique index if not exists stock_ledger_one_reversal on public.stock_ledger (reverses_id) where reverses_id is not null;
create unique index if not exists stock_ledger_one_opening on public.stock_ledger (item_id, location_id) where reason = 'opening';
create unique index if not exists stock_ledger_client on public.stock_ledger (client_id, reason) where client_id is not null;

create table if not exists public.stock_balance (
  item_id uuid not null references public.items(id),
  location_id int not null references public.locations(id),
  qty numeric not null default 0,
  avg_cost numeric,                                        -- weighted average per base unit. SECRET: not granted to the app roles
  updated_at timestamptz not null default now(),
  primary key (item_id, location_id)
);

create table if not exists public.stock_wastage (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id),
  location_id int not null references public.locations(id),
  qty numeric not null check (qty > 0),                    -- base unit
  reason_code text not null,                               -- from the editable list wastage_reasons
  note text, photo text,
  batch_id bigint references public.stock_batches(id),
  ledger_id bigint references public.stock_ledger(id),     -- first ledger row (a write-off that spans batches has several rows with ref_id = this id)
  made_at timestamptz not null default now(),
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create index if not exists stock_wastage_loc on public.stock_wastage (location_id, made_at);

create table if not exists public.stock_transfers (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  from_location_id int not null references public.locations(id),
  to_location_id int not null references public.locations(id),
  item_id uuid not null references public.items(id),
  qty numeric not null check (qty > 0),                    -- base unit, as sent
  status text not null default 'sent' check (status in ('sent', 'received', 'cancelled')),
  received_qty numeric check (received_qty is null or received_qty >= 0),
  note text, receive_note text,
  sent_by uuid, sent_staff text, sent_at timestamptz not null default now(),
  received_by uuid, received_staff text, received_at timestamptz,
  cancelled_by uuid, cancelled_at timestamptz,
  check (from_location_id <> to_location_id)
);
create index if not exists stock_transfers_open on public.stock_transfers (to_location_id) where status = 'sent';

create table if not exists public.purchase_bills (
  id uuid primary key default gen_random_uuid(),
  client_id uuid,
  kind text not null default 'bill' check (kind in ('bill', 'return')),         -- a return is money back from the supplier (a credit)
  supplier_id uuid not null references public.suppliers(id),
  bill_no text,                                            -- the supplier's own bill number
  bill_date date not null,
  location_id int not null references public.locations(id),
  status text not null default 'draft' check (status in ('draft', 'posted', 'void')),
  subtotal numeric not null default 0 check (subtotal >= 0),
  discount numeric not null default 0 check (discount >= 0),
  total numeric not null default 0 check (total >= 0),
  paid numeric not null default 0 check (paid >= 0),      -- paid at the time of posting (later payments are allocated oldest-first)
  due numeric generated always as (total - paid) stored,
  note text, photo text, reason_code text,
  ref_bill_id uuid references public.purchase_bills(id),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  posted_by uuid, posted_at timestamptz,
  void_by uuid, void_at timestamptz, void_note text,
  check (discount <= subtotal), check (paid <= total)
);
create unique index if not exists purchase_bills_client on public.purchase_bills (client_id) where client_id is not null;
create unique index if not exists purchase_bills_no on public.purchase_bills (supplier_id, lower(bill_no), kind) where bill_no is not null and status <> 'void';
create index if not exists purchase_bills_sup on public.purchase_bills (supplier_id, status);
create index if not exists purchase_bills_loc on public.purchase_bills (location_id, bill_date);

create table if not exists public.purchase_lines (
  id bigserial primary key,
  bill_id uuid not null references public.purchase_bills(id) on delete cascade,
  line_no int not null,
  item_id uuid references public.items(id),                -- null = a free-text, non-stock line (gas, transport ...)
  description text,
  qty numeric not null check (qty > 0),
  unit text,
  unit_cost numeric not null check (unit_cost >= 0),       -- SECRET (per the unit written on the line)
  amount numeric not null check (amount >= 0),
  base_qty numeric,                                        -- filled when posted (tracked items)
  unit_cost_base numeric,                                  -- per base unit, before the bill discount; filled when posted
  check (item_id is not null or nullif(btrim(description), '') is not null),
  unique (bill_id, line_no)
);

create table if not exists public.supplier_payments (
  id bigserial primary key,
  supplier_id uuid not null references public.suppliers(id),
  location_id int not null references public.locations(id),
  bill_id uuid references public.purchase_bills(id),       -- paid against one bill at posting; null = a general payment, allocated to the oldest bills
  kind text not null default 'payment' check (kind in ('payment')),
  mode text not null check (mode in ('cash', 'mobile', 'card', 'bank')),
  wallet text, ref text,
  amount numeric not null check (amount > 0),
  paid_at timestamptz not null default now(),
  note text,
  voided boolean not null default false, void_note text, void_by uuid,
  created_by uuid, created_staff text,
  client_id uuid
);
create index if not exists supplier_payments_sup on public.supplier_payments (supplier_id) where not voided;
create index if not exists supplier_payments_client on public.supplier_payments (client_id) where client_id is not null;
create index if not exists supplier_payments_loc on public.supplier_payments (location_id, paid_at);

-- audit trail for the changeable tables (the ledger itself needs none: it can never change)
drop trigger if exists audit_stock_transfers on public.stock_transfers;
create trigger audit_stock_transfers after insert or update on public.stock_transfers for each row execute function public.log_change('id');
drop trigger if exists audit_purchase_bills on public.purchase_bills;
create trigger audit_purchase_bills after insert or update on public.purchase_bills for each row execute function public.log_change('id');
drop trigger if exists audit_supplier_payments on public.supplier_payments;
create trigger audit_supplier_payments after insert or update on public.supplier_payments for each row execute function public.log_change('id');
drop trigger if exists audit_stock_wastage on public.stock_wastage;
create trigger audit_stock_wastage after insert on public.stock_wastage for each row execute function public.log_change('id');

-- ---------- (c) helpers (internal) ----------
-- management and the owner can work at every location
create or replace function public._all_locs() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = 'management'));
$$;

-- may the caller use grant p_code at location p_loc? owner / role / personal grant / approved emergency WINDOW (read only) or a ONE-USE emergency approval (consumed here)
create or replace function public._may(p_code text, p_loc int, p_ref text default 'stock', p_amount numeric default null) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  return public.has_grant(p_code, p_loc) or public.use_emergency(p_code, p_loc, p_ref, p_amount, null);
end $$;

-- may the caller see cost figures for this location?
create or replace function public._cost_ok(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost', p_loc));
$$;

-- may the caller read purchase / supplier-payable figures (they contain costs)? p_loc null = the whole company
create or replace function public._pur_ok(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (case when p_loc is null then public._all_locs() else public.can_loc(p_loc) end)
    and (public.is_owner() or public.has_grant('purchase_entry', p_loc) or public.has_grant('purchase_return', p_loc) or public.has_grant('supplier_pay', p_loc)
         or public.has_grant('purchase_void', p_loc) or public.has_grant('view_cost', p_loc));
$$;

create or replace function public._item_base(p_item uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(btrim(base_unit), ''), nullif(btrim(unit), '')) from public.items where id = p_item;
$$;

-- quantity written in p_unit -> item base unit. null when the conversion is unknown (nothing is guessed). No unit = already base.
create or replace function public._base_qty(p_item uuid, p_qty numeric, p_unit text) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare b text := public._item_base(p_item); f numeric;
begin
  if p_unit is null or btrim(p_unit) = '' or b is null or p_unit = b then return p_qty; end if;
  f := public.unit_factor(p_item, p_unit, b);
  if f is null then return null; end if;
  return p_qty * f;
end $$;
create or replace function public._unit_factor_base(p_item uuid, p_unit text) returns numeric      -- base units in ONE p_unit
language plpgsql stable security definer set search_path = public as $$
declare b text := public._item_base(p_item);
begin
  if p_unit is null or btrim(p_unit) = '' or b is null or p_unit = b then return 1; end if;
  return public.unit_factor(p_item, p_unit, b);
end $$;

-- weighted-average cost: the one rule used by the trigger and by the replay in stock_reconcile
--   in with a cost  -> (old_qty * old_avg + qty * cost) / (old_qty + qty)   (old stock <= 0 or unknown cost: the new cost)
--   out             -> average unchanged, except a reversal / purchase return of a costed receipt, which takes its cost back out
create or replace function public._avg_next(p_qty numeric, p_avg numeric, p_delta numeric, p_cost numeric, p_reason text) returns numeric
language plpgsql immutable as $$
declare r numeric;
begin
  if p_delta > 0 then
    if p_cost is null then return p_avg; end if;
    if p_avg is null or p_qty <= 0 then return round(p_cost, 6); end if;
    return round((p_qty * p_avg + p_delta * p_cost) / (p_qty + p_delta), 6);
  end if;
  if p_reason in ('reversal', 'purchase_return') and p_cost is not null and p_avg is not null and p_qty + p_delta > 0 then
    r := (p_qty * p_avg + p_delta * p_cost) / (p_qty + p_delta);
    if r >= 0 then return round(r, 6); end if;
  end if;
  return p_avg;
end $$;

-- one yellow / red line for the owner in the exceptions list (once per sale and flag)
create or replace function public._stock_exc(p_loc int, p_flag text, p_level text, p_bn text, p_en text, p_sale uuid default null, p_date date default null, p_form text default 'STOCK', p_amount numeric default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_sale is not null and exists (select 1 from public.exceptions where sale_id = p_sale and flag_code = p_flag) then return; end if;
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, p_sale, p_form, p_loc, coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date), p_flag, p_level, p_amount, jsonb_build_object('bn', p_bn, 'en', p_en));
end $$;

-- ---------- (d) the ledger: immutability and the balance cache ----------
create or replace function public._ledger_immutable() returns trigger
language plpgsql as $$
begin
  raise exception 'ledger_immutable' using hint = 'Fix a mistake with a reversing row, never by editing the ledger';
end $$;
drop trigger if exists stock_ledger_no_update on public.stock_ledger;
create trigger stock_ledger_no_update before update or delete on public.stock_ledger for each row execute function public._ledger_immutable();
drop trigger if exists stock_ledger_no_truncate on public.stock_ledger;
create trigger stock_ledger_no_truncate before truncate on public.stock_ledger for each statement execute function public._ledger_immutable();
drop trigger if exists stock_wastage_no_update on public.stock_wastage;
create trigger stock_wastage_no_update before update or delete on public.stock_wastage for each row execute function public._ledger_immutable();

-- every ledger row moves the cache in the same transaction (the caller already holds the row lock; this also covers a first row)
create or replace function public._ledger_to_balance() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.stock_balance set avg_cost = public._avg_next(qty, avg_cost, new.qty_delta, new.unit_cost, new.reason),
         qty = qty + new.qty_delta, updated_at = now()
   where item_id = new.item_id and location_id = new.location_id;
  if not found then
    insert into public.stock_balance (item_id, location_id, qty, avg_cost)
      values (new.item_id, new.location_id, new.qty_delta, public._avg_next(0, null, new.qty_delta, new.unit_cost, new.reason));
  end if;
  return new;
end $$;
drop trigger if exists stock_ledger_balance on public.stock_ledger;
create trigger stock_ledger_balance after insert on public.stock_ledger for each row execute function public._ledger_to_balance();

-- THE ONLY WRITER of the ledger. Internal (no app role may call it).  p_qty is in the BASE unit.
--   p_neg: 'full' = stock_negative_mode applies (allow / warn / block, block lifted by grant or emergency 'sell_below_zero')
--          'soft' = warn only (never blocks: reversals)   'none' = no check (opening, count adjustments, receipts)
-- A stock-out is taken from the oldest open batches first (a batch row per batch), the rest without a batch.  Returns the first ledger id.
create or replace function public.stock_post(p_item uuid, p_loc int, p_qty numeric, p_reason text, p_ref_type text default null, p_ref_id text default null,
  p_unit_cost numeric default null, p_batch bigint default null, p_made_at timestamptz default null, p_note text default null,
  p_reverses bigint default null, p_neg text default 'full', p_sale uuid default null, p_client uuid default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare q numeric := round(p_qty, 4); bal public.stock_balance; mode text; cost numeric; lid bigint; first_id bigint; b record; rem numeric; take numeric;
        ic text; nm text; at_ timestamptz := coalesce(p_made_at, now()); ref text := coalesce(p_ref_type, '') || ':' || coalesce(p_ref_id, '');
begin
  if q is null or q = 'NaN'::numeric or q = 0 then raise exception 'bad_qty'; end if;
  if p_neg not in ('full', 'soft', 'none') then raise exception 'bad_neg_mode'; end if;
  insert into public.stock_balance (item_id, location_id) values (p_item, p_loc) on conflict do nothing;
  select * into bal from public.stock_balance where item_id = p_item and location_id = p_loc for update;      -- serialises everyone touching this item here
  -- negative stock
  if q < 0 and p_neg <> 'none' and bal.qty + q < 0 then
    mode := coalesce(public.rule_txt('stock_negative_mode'), 'warn');
    if mode <> 'allow' then
      select code, name_bn into ic, nm from public.items where id = p_item;
      if mode = 'block' and p_neg = 'full' then
        if not public._may('sell_below_zero', p_loc, ref) then
          raise exception 'insufficient_stock' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'on hand ' || bal.qty::text;
        end if;
      end if;
      perform public._stock_exc(p_loc, 'stock_negative', 'yellow',
        coalesce(nm, '') || ' (' || coalesce(ic, '') || '): স্টকের চেয়ে বেশি বের হয়েছে — হিসাবে স্টক ঋণাত্মক',
        coalesce(nm, '') || ' (' || coalesce(ic, '') || '): more went out than the stock on hand — the stock is now negative',
        p_sale, (at_ at time zone 'Asia/Dhaka')::date, case when p_sale is not null then 'POS' else 'STOCK' end);
    end if;
  end if;
  cost := coalesce(p_unit_cost, case when q < 0 then bal.avg_cost end);
  if q < 0 and p_batch is null and p_reason in ('sale_out', 'issue_out', 'wastage', 'transfer_out', 'count_adjust', 'purchase_return') then
    rem := -q;
    for b in select id, qty_remaining from public.stock_batches where item_id = p_item and location_id = p_loc and qty_remaining > 0
             order by expires_at nulls last, made_at, id for update loop
      take := least(b.qty_remaining, rem);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -take, cost, p_reason, p_ref_type, p_ref_id, b.id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      update public.stock_batches set qty_remaining = qty_remaining - take where id = b.id;
      first_id := coalesce(first_id, lid); rem := rem - take;
      exit when rem <= 0;
    end loop;
    if rem > 0 then
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -rem, cost, p_reason, p_ref_type, p_ref_id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      first_id := coalesce(first_id, lid);
    end if;
    return first_id;
  end if;
  insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
    values (p_item, p_loc, q, cost, p_reason, p_ref_type, p_ref_id, p_batch, p_reverses, p_client, at_, p_note, auth.uid()) returning id into lid;
  if p_batch is not null then
    if q < 0 then
      update public.stock_batches set qty_remaining = qty_remaining + q where id = p_batch and qty_remaining + q >= 0;
      if not found then raise exception 'batch_short'; end if;
    elsif p_reason in ('sale_void_in', 'reversal') then
      update public.stock_batches set qty_remaining = least(qty_made, qty_remaining + q) where id = p_batch;
    end if;
  end if;
  return lid;
end $$;

-- ---------- (e) POS hook: sale_out when a sale is saved, sale_void_in when it is voided (tracked items only; record_sale2 is NOT changed) ----------
create or replace function public._sale_stock_out() returns trigger
language plpgsql security definer set search_path = public as $$
declare ln jsonb; it public.items; q numeric; bq numeric;
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  -- items in a fixed order, so two sales that share items can never wait on each other in a circle
  for ln in select x from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null order by x->>'item_id' loop
    select * into it from public.items where id = (ln->>'item_id')::uuid;
    if not found or not it.tracked then continue; end if;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or q <= 0 then continue; end if;
    bq := public._base_qty(it.id, q, ln->>'unit');
    if bq is null then
      perform public._stock_exc(new.location_id, 'stock_unit_unknown', 'yellow',
        'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — এককের রূপান্তর জানা নেই, স্টক কমানো হয়নি',
        'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');
      continue;
    end if;
    perform public.stock_post(it.id, new.location_id, -bq, 'sale_out', 'sale', new.id::text, null, null, new.sold_at, null, null, 'full', new.id);
  end loop;
  return new;
end $$;
drop trigger if exists sales_stock_out on public.sales;
create trigger sales_stock_out after insert on public.sales for each row execute function public._sale_stock_out();

create or replace function public._sale_stock_void() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.stock_ledger;
begin
  for r in select * from public.stock_ledger o where o.ref_type = 'sale' and o.ref_id = new.id::text and o.reason = 'sale_out'
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'sale_void_in', 'sale', new.id::text, r.unit_cost, r.batch_id, now(), null, r.id, 'none', new.id);
  end loop;
  return new;
end $$;
drop trigger if exists sales_stock_void on public.sales;
create trigger sales_stock_void after update of status on public.sales for each row
  when (old.status is distinct from 'void' and new.status = 'void') execute function public._sale_stock_void();

-- ---------- (f) stock functions (all SECURITY DEFINER) ----------
-- checks shared by the manual stock functions: item tracked, caller allowed at the location, period open
create or replace function public._stock_guard(p_item uuid, p_loc int, p_grant text, p_date date default null) returns public.items
language plpgsql security definer set search_path = public as $$
declare it public.items;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select * into it from public.items where id = p_item;
  if not found or not it.is_active then raise exception 'item_not_found'; end if;
  if not it.tracked then raise exception 'item_not_tracked'; end if;
  if p_date is not null then perform public.lock_check(p_date); end if;
  return it;
end $$;

-- counted opening balance: once per item and location (a later error is fixed with stock_count_adjust)
create or replace function public.stock_opening(p_item uuid, p_loc int, p_qty numeric, p_unit_cost numeric default null, p_unit text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; f numeric; cost numeric; lid bigint;
begin
  it := public._stock_guard(p_item, p_loc, 'stock_opening', (now() at time zone 'Asia/Dhaka')::date);
  if p_client is not null then select id into lid from public.stock_ledger where client_id = p_client and reason = 'opening'; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if; end if;
  if p_qty is null or p_qty = 'NaN'::numeric or p_qty <= 0 then raise exception 'bad_qty'; end if;
  if p_unit_cost is not null and (p_unit_cost = 'NaN'::numeric or p_unit_cost < 0) then raise exception 'bad_cost'; end if;
  if not public._may('stock_opening', p_loc, 'opening:' || p_item::text) then raise exception 'not allowed'; end if;
  perform 1 from public.items where id = p_item for update;                       -- two people entering the same opening wait here
  if exists (select 1 from public.stock_ledger where item_id = p_item and location_id = p_loc and reason = 'opening') then raise exception 'opening_exists'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  f := public._unit_factor_base(p_item, p_unit);
  cost := case when p_unit_cost is null then null else p_unit_cost / f end;       -- cost given per p_unit -> per base unit
  lid := public.stock_post(p_item, p_loc, bq, 'opening', 'opening', null, cost, null, now(), left(p_note, 200), null, 'none', null, p_client);
  return jsonb_build_object('ledger_id', lid, 'qty', bq);
end $$;

-- write off wasted stock. Reason from the editable list wastage_reasons. Photo required above the owner's quantity limit (rule wastage_photo_above, empty = off).
create or replace function public.stock_wastage(p_item uuid, p_loc int, p_qty numeric, p_reason text, p_note text default null, p_photo text default null,
  p_unit text default null, p_client uuid default null, p_batch bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; lid bigint; wid uuid := gen_random_uuid(); lim numeric; sid text; nm text;
begin
  it := public._stock_guard(p_item, p_loc, 'wastage_write_off', (now() at time zone 'Asia/Dhaka')::date);
  if p_client is not null then select id into lid from public.stock_ledger where client_id = p_client and reason = 'wastage'; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if; end if;
  if p_qty is null or p_qty = 'NaN'::numeric or p_qty <= 0 then raise exception 'bad_qty'; end if;
  if p_reason is null or not exists (select 1 from public.option_lists where list_code = 'wastage_reasons' and value_code = p_reason and active) then raise exception 'bad_reason'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  lim := public.rule_num('wastage_photo_above');
  if lim is not null and bq > lim and nullif(btrim(p_photo), '') is null then raise exception 'photo_required'; end if;
  if length(coalesce(p_photo, '')) > 300 then raise exception 'bad_photo'; end if;
  if not public._may('wastage_write_off', p_loc, 'wastage:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  if p_batch is not null and not exists (select 1 from public.stock_batches where id = p_batch and item_id = p_item and location_id = p_loc) then raise exception 'batch_not_found'; end if;
  lid := public.stock_post(p_item, p_loc, -bq, 'wastage', 'wastage', wid::text, null, p_batch, now(), left(p_note, 200), null, 'full', null, p_client);
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.stock_wastage (id, item_id, location_id, qty, reason_code, note, photo, batch_id, ledger_id, created_by, created_staff)
    values (wid, p_item, p_loc, bq, p_reason, left(p_note, 200), nullif(btrim(p_photo), ''), p_batch, lid, auth.uid(), sid);
  if p_reason = 'unknown' then
    nm := it.name_bn;
    perform public._stock_exc(p_loc, 'wastage_unknown', 'yellow', nm || ': নষ্ট মাল বাদ দেওয়া হয়েছে কিন্তু কারণ অজানা', coalesce(it.name_en, nm) || ': stock was written off with an unknown reason');
  end if;
  return jsonb_build_object('id', wid, 'ledger_id', lid, 'qty', bq);
end $$;

-- move the end-of-day unsold / expired part of ONE batch to wastage
create or replace function public.stock_expire_batch(p_batch bigint, p_reason text default 'expired', p_note text default null, p_photo text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.stock_batches;
begin
  select * into b from public.stock_batches where id = p_batch;
  if not found then raise exception 'batch_not_found'; end if;
  if b.qty_remaining <= 0 then raise exception 'batch_empty'; end if;
  return public.stock_wastage(b.item_id, b.location_id, b.qty_remaining, p_reason, p_note, p_photo, null, null, b.id);
end $$;

-- the physical count says p_counted: post the difference (needs a note). Tolerance rule count_tolerance_pct (empty = off) only informs the owner.
create or replace function public.stock_count_adjust(p_item uuid, p_loc int, p_counted numeric, p_note text, p_unit text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; bal public.stock_balance; d numeric; lid bigint; tol numeric;
begin
  it := public._stock_guard(p_item, p_loc, 'stock_count_adjust', (now() at time zone 'Asia/Dhaka')::date);
  if p_client is not null then select id into lid from public.stock_ledger where client_id = p_client and reason = 'count_adjust'; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if; end if;
  if p_counted is null or p_counted = 'NaN'::numeric or p_counted < 0 then raise exception 'bad_qty'; end if;
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  bq := public._base_qty(p_item, p_counted, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not public._may('stock_count_adjust', p_loc, 'count:' || p_item::text) then raise exception 'not allowed'; end if;
  insert into public.stock_balance (item_id, location_id) values (p_item, p_loc) on conflict do nothing;
  select * into bal from public.stock_balance where item_id = p_item and location_id = p_loc for update;
  d := round(bq - bal.qty, 4);
  if d = 0 then return jsonb_build_object('ledger_id', null, 'delta', 0, 'qty', bal.qty); end if;
  lid := public.stock_post(p_item, p_loc, d, 'count_adjust', 'count', null, null, null, now(), left(p_note, 200), null, 'none', null, p_client);
  tol := public.rule_num('count_tolerance_pct');
  if tol is not null and (bal.qty = 0 or abs(d) / abs(bal.qty) * 100 > tol) then
    perform public._stock_exc(p_loc, 'count_variance', 'yellow', it.name_bn || ': গণনায় ' || d::text || ' পার্থক্য', coalesce(it.name_en, it.name_bn) || ': the count differs from the book by ' || d::text);
  end if;
  return jsonb_build_object('ledger_id', lid, 'delta', d, 'qty', bq);
end $$;

-- material issued to production
create or replace function public.stock_issue(p_item uuid, p_loc int, p_qty numeric, p_unit text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; lid bigint;
begin
  it := public._stock_guard(p_item, p_loc, 'stock_issue', (now() at time zone 'Asia/Dhaka')::date);
  if p_client is not null then select id into lid from public.stock_ledger where client_id = p_client and reason = 'issue_out'; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if; end if;
  if p_qty is null or p_qty = 'NaN'::numeric or p_qty <= 0 then raise exception 'bad_qty'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not public._may('stock_issue', p_loc, 'issue:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  lid := public.stock_post(p_item, p_loc, -bq, 'issue_out', 'issue', null, null, null, now(), left(p_note, 200), null, 'full', null, p_client);
  return jsonb_build_object('ledger_id', lid, 'qty', bq);
end $$;

-- finished goods made: stock in + a batch whose expiry comes from the owner's shelf-life rules (no rule = no expiry, expires_at null)
create or replace function public.stock_production_in(p_item uuid, p_loc int, p_qty numeric, p_made_at timestamptz default null, p_unit text default null,
  p_note text default null, p_client uuid default null, p_unit_cost numeric default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; lid bigint; at_ timestamptz := coalesce(p_made_at, now()); sl jsonb; exp timestamptz; bid bigint; f numeric;
begin
  it := public._stock_guard(p_item, p_loc, 'stock_production', (at_ at time zone 'Asia/Dhaka')::date);
  if p_client is not null then select id, batch_id into lid, bid from public.stock_ledger where client_id = p_client and reason = 'production_in'; if found then return jsonb_build_object('dup', true, 'ledger_id', lid, 'batch_id', bid); end if; end if;
  if p_qty is null or p_qty = 'NaN'::numeric or p_qty <= 0 then raise exception 'bad_qty'; end if;
  if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  if p_unit_cost is not null and (p_unit_cost = 'NaN'::numeric or p_unit_cost < 0) then raise exception 'bad_cost'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not public._may('stock_production', p_loc, 'production:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  f := public._unit_factor_base(p_item, p_unit);
  sl := public.shelf_life_for(p_item, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (p_item, p_loc, at_, bq, bq, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  lid := public.stock_post(p_item, p_loc, bq, 'production_in', 'production', bid::text, case when p_unit_cost is null then null else p_unit_cost / f end, bid, at_, left(p_note, 200), null, 'none', null, p_client);
  return jsonb_build_object('ledger_id', lid, 'batch_id', bid, 'qty', bq, 'expires_at', exp);
end $$;

-- transfer: OUT at the sender at once, IN at the receiver only when they receive it (in between it is "in transit", not lost)
create or replace function public.stock_transfer(p_from int, p_to int, p_item uuid, p_qty numeric, p_unit text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; tid uuid := gen_random_uuid(); sid text; t public.stock_transfers; lid bigint;
begin
  it := public._stock_guard(p_item, p_from, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  if p_client is not null then
    select * into t from public.stock_transfers where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  end if;
  if p_to is null or p_to = p_from or not exists (select 1 from public.locations where id = p_to) then raise exception 'bad_location'; end if;
  if p_qty is null or p_qty = 'NaN'::numeric or p_qty <= 0 then raise exception 'bad_qty'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not public._may('stock_transfer', p_from, 'transfer:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.stock_transfers (id, client_id, from_location_id, to_location_id, item_id, qty, note, sent_by, sent_staff)
    values (tid, p_client, p_from, p_to, p_item, bq, left(p_note, 200), auth.uid(), sid);
  lid := public.stock_post(p_item, p_from, -bq, 'transfer_out', 'transfer', tid::text, null, null, now(), left(p_note, 200), null, 'full');
  return jsonb_build_object('id', tid, 'status', 'sent', 'qty', bq);
end $$;

-- the destination receives (p_received_qty in the BASE unit, default = all that was sent). Less than sent -> an exception (transit_short).
create or replace function public.stock_receive_transfer(p_id uuid, p_received_qty numeric default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.stock_transfers; it public.items; rq numeric; sid text; o record; rem numeric; take numeric; nb bigint; cost numeric; ob public.stock_batches; lid bigint;
begin
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if t.status = 'received' then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  if t.status <> 'sent' then raise exception 'not_in_transit'; end if;
  it := public._stock_guard(t.item_id, t.to_location_id, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  if not public._may('stock_transfer', t.to_location_id, 'receive:' || p_id::text, t.qty) then raise exception 'not allowed'; end if;
  rq := coalesce(p_received_qty, t.qty);
  if rq = 'NaN'::numeric or rq < 0 then raise exception 'bad_qty'; end if;
  if rq > t.qty then raise exception 'over_received'; end if;
  rem := rq;
  for o in select * from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transfer_out' order by id loop
    exit when rem <= 0;
    take := least(-o.qty_delta, rem);
    nb := null;
    if o.batch_id is not null then       -- the batch travels with the goods: same made-at and expiry at the destination
      select * into ob from public.stock_batches where id = o.batch_id;
      insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
        values (t.item_id, t.to_location_id, ob.made_at, take, take, ob.expires_at, ob.shelf_rule, 'transfer', auth.uid()) returning id into nb;
    end if;
    lid := public.stock_post(t.item_id, t.to_location_id, take, 'transfer_in', 'transfer', t.id::text, o.unit_cost, nb, now(), left(p_note, 200), null, 'none');
    rem := rem - take;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.stock_transfers set status = 'received', received_qty = rq, receive_note = left(p_note, 200), received_by = auth.uid(), received_staff = sid, received_at = now() where id = t.id;
  if rq < t.qty then
    perform public._stock_exc(t.to_location_id, 'transit_short', 'yellow',
      it.name_bn || ': পাঠানো ' || t.qty::text || ', গ্রহণ ' || rq::text || ' — পথে কম', coalesce(it.name_en, it.name_bn) || ': sent ' || t.qty::text || ', received ' || rq::text || ' — short in transit');
  end if;
  return jsonb_build_object('id', t.id, 'status', 'received', 'received_qty', rq, 'short', t.qty - rq);
end $$;

-- the sender takes back a transfer that is still in transit (a reversing row)
create or replace function public.stock_cancel_transfer(p_id uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.stock_transfers; o public.stock_ledger;
begin
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if t.status = 'cancelled' then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  if t.status <> 'sent' then raise exception 'not_in_transit'; end if;
  perform public._stock_guard(t.item_id, t.from_location_id, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  if not (t.sent_by = auth.uid() or public.is_owner() or public.has_grant('stock_transfer', t.from_location_id)) then raise exception 'not allowed'; end if;
  for o in select * from public.stock_ledger x where x.ref_type = 'transfer' and x.ref_id = t.id::text and x.reason = 'transfer_out' order by x.id loop
    perform public.stock_post(o.item_id, o.location_id, -o.qty_delta, 'reversal', 'transfer', t.id::text, o.unit_cost, o.batch_id, now(), left(p_note, 200), o.id, 'none');
  end loop;
  update public.stock_transfers set status = 'cancelled', cancelled_by = auth.uid(), cancelled_at = now(), receive_note = left(p_note, 200) where id = t.id;
  return jsonb_build_object('id', t.id, 'status', 'cancelled');
end $$;

-- ---------- (g) stock reads ----------
-- stock on hand. p_filters: {"category":"..","q":"name or code","below_min":true,"include_zero":true,"item_ids":["uuid",..]}
-- Staff see quantities at their own locations; avg_cost and value only where the caller may see cost.
create or replace function public.stock_levels(p_loc int default null, p_filters jsonb default '{}'::jsonb)
returns table (item_id uuid, code text, name_bn text, name_en text, category text, base_unit text, location_id int, qty numeric, min_stock numeric, below_min boolean, avg_cost numeric, value numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare f jsonb := coalesce(p_filters, '{}'::jsonb); ids uuid[];
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if f ? 'item_ids' and jsonb_typeof(f->'item_ids') = 'array' then select array_agg(x::uuid) into ids from jsonb_array_elements_text(f->'item_ids') x; end if;
  return query
    select i.id, i.code, i.name_bn, i.name_en, i.category, public._item_base(i.id), l.id,
           coalesce(b.qty, 0), i.min_stock,
           (i.min_stock is not null and coalesce(b.qty, 0) < i.min_stock),
           case when public._cost_ok(l.id) then b.avg_cost end,
           case when public._cost_ok(l.id) and b.avg_cost is not null then round(b.qty * b.avg_cost, 2) end
    from public.items i
    cross join public.locations l
    left join public.stock_balance b on b.item_id = i.id and b.location_id = l.id
    where i.tracked and i.is_active
      and public.can_loc(l.id) and (p_loc is null or l.id = p_loc)
      and (b.item_id is not null or p_loc is not null)
      and (coalesce((f->>'include_zero')::boolean, false) or p_loc is not null or coalesce(b.qty, 0) <> 0)
      and (f->>'category' is null or i.category = f->>'category')
      and (f->>'q' is null or i.name_bn ilike '%' || (f->>'q') || '%' or i.name_en ilike '%' || (f->>'q') || '%' or i.code ilike '%' || (f->>'q') || '%')
      and (ids is null or i.id = any (ids))
      and (not coalesce((f->>'below_min')::boolean, false) or (i.min_stock is not null and coalesce(b.qty, 0) < i.min_stock))
    order by i.code, l.id;
end $$;

-- weighted-average cost of an item at a location: null for anyone who may not see cost
create or replace function public.stock_avg_cost(p_item uuid, p_loc int) returns numeric
language sql stable security definer set search_path = public as $$
  select case when public._cost_ok(p_loc) and public.can_loc(p_loc) then (select avg_cost from public.stock_balance where item_id = p_item and location_id = p_loc) end;
$$;

-- the movements of one item / location (cost shown only to those who may see it)
create or replace function public.stock_ledger_rows(p_loc int, p_item uuid default null, p_from date default null, p_to date default null, p_limit int default 200)
returns table (id bigint, item_id uuid, location_id int, qty_delta numeric, unit_cost numeric, reason text, ref_type text, ref_id text, batch_id bigint, made_at timestamptz, note text, created_by uuid, reverses_id bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return query
    select l.id, l.item_id, l.location_id, l.qty_delta, case when public._cost_ok(l.location_id) then l.unit_cost end, l.reason, l.ref_type, l.ref_id, l.batch_id, l.made_at, l.note, l.created_by, l.reverses_id
    from public.stock_ledger l
    where l.location_id = p_loc and (p_item is null or l.item_id = p_item)
      and (p_from is null or (l.made_at at time zone 'Asia/Dhaka')::date >= p_from) and (p_to is null or (l.made_at at time zone 'Asia/Dhaka')::date <= p_to)
    order by l.id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000);
end $$;

-- goods on the way
create or replace function public.stock_in_transit(p_loc int default null)
returns table (id uuid, item_id uuid, code text, name_bn text, from_location_id int, to_location_id int, qty numeric, sent_at timestamptz, sent_staff text, note text)
language sql stable security definer set search_path = public as $$
  select t.id, t.item_id, i.code, i.name_bn, t.from_location_id, t.to_location_id, t.qty, t.sent_at, t.sent_staff, t.note
  from public.stock_transfers t join public.items i on i.id = t.item_id
  where t.status = 'sent' and (public.can_loc(t.from_location_id) or public.can_loc(t.to_location_id))
    and (p_loc is null or t.from_location_id = p_loc or t.to_location_id = p_loc)
  order by t.sent_at;
$$;

-- batches that expire within p_hours_ahead hours (already expired ones included). No shelf-life rule -> the batch has no expiry and never shows here.
create or replace function public.expiry_list(p_loc int default null, p_hours_ahead numeric default 24)
returns table (batch_id bigint, item_id uuid, code text, name_bn text, name_en text, location_id int, made_at timestamptz, expires_at timestamptz, qty_remaining numeric, hours_left numeric, expired boolean)
language sql stable security definer set search_path = public as $$
  select b.id, b.item_id, i.code, i.name_bn, i.name_en, b.location_id, b.made_at, b.expires_at, b.qty_remaining,
         round((extract(epoch from (b.expires_at - now())) / 3600)::numeric, 2), b.expires_at <= now()
  from public.stock_batches b join public.items i on i.id = b.item_id
  where b.qty_remaining > 0 and b.expires_at is not null and public.can_loc(b.location_id)
    and (p_loc is null or b.location_id = p_loc)
    and b.expires_at <= now() + (coalesce(p_hours_ahead, 24)::float8 * interval '1 hour')
  order by b.expires_at, b.id;
$$;

-- stock value at average cost (cost-gated: only locations where the caller may see cost)
create or replace function public.stock_valuation(p_loc int default null)
returns table (location_id int, item_id uuid, code text, name_bn text, qty numeric, avg_cost numeric, value numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not (public.can_loc(p_loc) and public._cost_ok(p_loc)) then raise exception 'not allowed'; end if;
  return query
    select b.location_id, b.item_id, i.code, i.name_bn, b.qty, b.avg_cost, round(b.qty * b.avg_cost, 2)
    from public.stock_balance b join public.items i on i.id = b.item_id
    where b.qty <> 0 and b.avg_cost is not null and (p_loc is null or b.location_id = p_loc)
      and public.can_loc(b.location_id) and public._cost_ok(b.location_id)
    order by b.location_id, i.code;
end $$;

-- owner: does the cache equal the ledger?  p_fix = true rewrites the CACHE (never the ledger) from the ledger.
create or replace function public.stock_reconcile(p_fix boolean default false)
returns table (item_id uuid, location_id int, ledger_qty numeric, cached_qty numeric, qty_diff numeric, cached_avg numeric, replay_avg numeric)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare r record; l record; q numeric; a numeric;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  for r in
    select coalesce(s.item_id, b.item_id) iid, coalesce(s.location_id, b.location_id) lid, coalesce(s.sq, 0) sq, coalesce(b.qty, 0) bq, b.avg_cost bavg
    from (select item_id, location_id, sum(qty_delta) sq from public.stock_ledger group by 1, 2) s
    full join public.stock_balance b on b.item_id = s.item_id and b.location_id = s.location_id loop
    q := 0; a := null;
    for l in select qty_delta, unit_cost, reason from public.stock_ledger x where x.item_id = r.iid and x.location_id = r.lid order by x.id loop
      a := public._avg_next(q, a, l.qty_delta, l.unit_cost, l.reason); q := q + l.qty_delta;
    end loop;
    if r.sq <> r.bq or r.bavg is distinct from a then
      item_id := r.iid; location_id := r.lid; ledger_qty := r.sq; cached_qty := r.bq; qty_diff := r.bq - r.sq; cached_avg := r.bavg; replay_avg := a;
      if p_fix then
        insert into public.stock_balance (item_id, location_id, qty, avg_cost) values (r.iid, r.lid, r.sq, a)
          on conflict (item_id, location_id) do update set qty = excluded.qty, avg_cost = excluded.avg_cost, updated_at = now();
      end if;
      return next;
    end if;
  end loop;
end $$;

-- ---------- (h) purchases and the supplier ledger ----------
-- Supplier balance = opening + posted bills - returns - payments (positive = we owe). Payments made with a bill are tied to it; later (general)
-- payments and returns clear the OLDEST open bills first, the same idea as customer dues. The allocation is computed, never stored, so a void just re-flows.
create or replace function public._sup_open(p_supplier uuid default null)
returns table (supplier_id uuid, bill_id uuid, bill_no text, bill_date date, location_id int, rem numeric, open_amt numeric)
language sql stable security definer set search_path = public as $$
  with bills as (
    select b.supplier_id, b.id bill_id, b.bill_no, b.bill_date, b.location_id, b.total - b.paid rem, coalesce(b.posted_at, b.created_at) ord_at
    from public.purchase_bills b where b.status = 'posted' and b.kind = 'bill' and b.total - b.paid > 0 and (p_supplier is null or b.supplier_id = p_supplier)
    union all
    select s.id, null, 'opening', null, null, s.opening_balance, '-infinity'::timestamptz
    from public.suppliers s where s.opening_balance > 0 and (p_supplier is null or s.id = p_supplier)),
  cr as (
    select supplier_id, sum(x) credit from (
      select p.supplier_id, p.amount x from public.supplier_payments p where not p.voided and p.bill_id is null and (p_supplier is null or p.supplier_id = p_supplier)
      union all select b.supplier_id, b.total from public.purchase_bills b where b.status = 'posted' and b.kind = 'return' and (p_supplier is null or b.supplier_id = p_supplier)
      union all select s.id, -s.opening_balance from public.suppliers s where s.opening_balance < 0 and (p_supplier is null or s.id = p_supplier)) z group by 1),
  cum as (select bills.*, sum(rem) over (partition by bills.supplier_id order by bills.bill_date nulls first, bills.ord_at, bills.bill_id) c from bills)
  select cum.supplier_id, cum.bill_id, cum.bill_no, cum.bill_date, cum.location_id, cum.rem,
         cum.rem - least(cum.rem, greatest(0, coalesce(cr.credit, 0) - (cum.c - cum.rem)))
  from cum left join cr on cr.supplier_id = cum.supplier_id;
$$;

create or replace function public._sup_balance(p_supplier uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select opening_balance from public.suppliers where id = p_supplier), 0)
       + coalesce((select sum(case kind when 'bill' then total else -total end) from public.purchase_bills where supplier_id = p_supplier and status = 'posted'), 0)
       - coalesce((select sum(amount) from public.supplier_payments where supplier_id = p_supplier and not voided), 0);
$$;

-- write (or change, while it is still a draft) a purchase bill / return. Lines: [{"item_id":uuid | "description":"gas cylinder","qty":10,"unit":"kg","unit_cost":120}]
-- p_client makes a re-sent request return the same bill. Totals are computed here.
create or replace function public.save_purchase(p_client uuid, p_id uuid, p_supplier uuid, p_loc int, p_bill_no text, p_bill_date date, p_lines jsonb,
  p_discount numeric default 0, p_note text default null, p_photo text default null, p_kind text default 'bill', p_ref_bill uuid default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills; ln jsonb; it public.items; n int := 0; qty numeric; uc numeric; amt numeric; sub numeric := 0; disc numeric := coalesce(p_discount, 0);
        un text; bid uuid := p_id; sid text; ref public.purchase_bills; gcode text;
begin
  if p_kind not in ('bill', 'return') then raise exception 'bad_kind'; end if;
  gcode := case p_kind when 'return' then 'purchase_return' else 'purchase_entry' end;
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_client is not null then
    select * into pb from public.purchase_bills where client_id = p_client;
    if found then
      if pb.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('id', pb.id, 'status', pb.status, 'total', pb.total, 'dup', true);
    end if;
  end if;
  if bid is not null then
    select * into pb from public.purchase_bills where id = bid for update;
    if not found then raise exception 'not found'; end if;
    if pb.status <> 'draft' then raise exception 'not_draft'; end if;
    if pb.kind <> p_kind or pb.location_id <> p_loc then raise exception 'cannot_change_kind_or_location'; end if;
  end if;
  if not (public.has_grant(gcode, p_loc) or public.use_emergency(gcode, p_loc, 'save_purchase', null, null)) then raise exception 'not allowed'; end if;
  if p_bill_date is null or p_bill_date > (now() at time zone 'Asia/Dhaka')::date + 1 then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.suppliers where id = p_supplier and active) then raise exception 'supplier_not_found'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if disc = 'NaN'::numeric or disc < 0 then raise exception 'bad_discount'; end if;
  if length(coalesce(p_photo, '')) > 300 then raise exception 'bad_photo'; end if;
  if p_kind = 'return' then
    if p_reason is null or not exists (select 1 from public.option_lists where list_code = 'return_reasons' and value_code = p_reason and active) then raise exception 'reason_required'; end if;
    if p_ref_bill is not null then
      select * into ref from public.purchase_bills where id = p_ref_bill;
      if not found or ref.supplier_id <> p_supplier or ref.kind <> 'bill' then raise exception 'bad_ref_bill'; end if;
    end if;
  elsif p_ref_bill is not null then raise exception 'bad_ref_bill';
  end if;
  if nullif(btrim(p_bill_no), '') is not null and exists (select 1 from public.purchase_bills where supplier_id = p_supplier and lower(bill_no) = lower(btrim(p_bill_no)) and kind = p_kind and status <> 'void' and id is distinct from bid) then
    raise exception 'duplicate_bill';
  end if;
  -- validate lines first (nothing is written if one is wrong)
  for ln in select * from jsonb_array_elements(p_lines) loop
    qty := nullif(ln->>'qty', '')::numeric; uc := nullif(ln->>'unit_cost', '')::numeric;
    if qty is null or qty = 'NaN'::numeric or qty <= 0 then raise exception 'bad_qty'; end if;
    if uc is null or uc = 'NaN'::numeric or uc < 0 then raise exception 'bad_cost'; end if;
    if nullif(ln->>'item_id', '') is not null then
      select * into it from public.items where id = (ln->>'item_id')::uuid;
      if not found or not it.is_active then raise exception 'item_not_found'; end if;
      if it.tracked and public._base_qty(it.id, 1, coalesce(nullif(ln->>'unit', ''), it.unit)) is null then raise exception 'unit_unknown'; end if;
    elsif nullif(btrim(ln->>'description'), '') is null then raise exception 'description_required';
    end if;
    sub := sub + round(qty * uc, 2);
  end loop;
  if disc > sub then raise exception 'bad_discount'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if bid is null then
    begin
      insert into public.purchase_bills (client_id, kind, supplier_id, bill_no, bill_date, location_id, status, subtotal, discount, total, note, photo, reason_code, ref_bill_id, created_by, created_staff)
        values (p_client, p_kind, p_supplier, nullif(btrim(p_bill_no), ''), p_bill_date, p_loc, 'draft', sub, round(disc, 2), sub - round(disc, 2), left(p_note, 300), nullif(btrim(p_photo), ''), p_reason, p_ref_bill, auth.uid(), sid)
        returning id into bid;
    exception when unique_violation then
      select * into pb from public.purchase_bills where client_id = p_client;
      if found and pb.created_by = auth.uid() then return jsonb_build_object('id', pb.id, 'status', pb.status, 'total', pb.total, 'dup', true); end if;
      raise exception 'duplicate_bill';
    end;
  else
    update public.purchase_bills set supplier_id = p_supplier, bill_no = nullif(btrim(p_bill_no), ''), bill_date = p_bill_date, subtotal = sub, discount = round(disc, 2), total = sub - round(disc, 2),
      note = left(p_note, 300), photo = nullif(btrim(p_photo), ''), reason_code = p_reason, ref_bill_id = p_ref_bill where id = bid;
    delete from public.purchase_lines where bill_id = bid;
  end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    n := n + 1; qty := (ln->>'qty')::numeric; uc := (ln->>'unit_cost')::numeric; amt := round(qty * uc, 2); un := null; it := null;
    if nullif(ln->>'item_id', '') is not null then
      select * into it from public.items where id = (ln->>'item_id')::uuid;
      un := coalesce(nullif(ln->>'unit', ''), it.unit);
    else un := nullif(ln->>'unit', '');
    end if;
    insert into public.purchase_lines (bill_id, line_no, item_id, description, qty, unit, unit_cost, amount)
      values (bid, n, it.id, left(nullif(btrim(ln->>'description'), ''), 120), qty, left(un, 20), uc, amt);
  end loop;
  return jsonb_build_object('id', bid, 'status', 'draft', 'total', sub - round(disc, 2), 'lines', n);
end $$;

-- post a draft: stock IN (or OUT for a return) for tracked items with the weighted-average update, the payable, and optional payments made at once
-- p_payments: [{"mode":"cash","wallet":null,"ref":null,"amount":500}]  (needs the grant supplier_pay)
create or replace function public.post_purchase(p_id uuid, p_payments jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills; ln record; it public.items; gcode text; f numeric; bq numeric; ucb numeric; net numeric; last_c numeric; jump numeric; pct numeric; sid text;
        pay jsonb; pm text; amt numeric; psum numeric := 0; jumped boolean := false; nm text;
begin
  select * into pb from public.purchase_bills where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if pb.status = 'posted' then return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'dup', true); end if;
  if pb.status <> 'draft' then raise exception 'not_draft'; end if;
  gcode := case pb.kind when 'return' then 'purchase_return' else 'purchase_entry' end;
  if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.has_grant(gcode, pb.location_id) or public.use_emergency(gcode, pb.location_id, 'post_purchase:' || p_id::text, pb.total, null)) then raise exception 'not allowed'; end if;
  if public.rule_on('purchase_separate_poster') and pb.created_by = auth.uid() and not public.is_owner() then raise exception 'poster_must_differ'; end if;
  perform public.lock_check(pb.bill_date);
  if pb.subtotal = 0 and pb.total = 0 and not exists (select 1 from public.purchase_lines where bill_id = pb.id) then raise exception 'no_lines'; end if;
  pct := public.rule_num('purchase_cost_jump_pct');
  net := case when pb.subtotal > 0 then (pb.subtotal - pb.discount) / pb.subtotal else 1 end;         -- the bill discount is spread over the lines
  for ln in select * from public.purchase_lines where bill_id = pb.id order by item_id nulls last, line_no loop
    if ln.item_id is null then continue; end if;
    select * into it from public.items where id = ln.item_id;
    f := public._unit_factor_base(ln.item_id, ln.unit);
    if f is null or f <= 0 then
      if it.tracked then raise exception 'unit_unknown'; end if;
      f := 1;
    end if;
    bq := ln.qty * f; ucb := ln.unit_cost / f;
    update public.purchase_lines set base_qty = bq, unit_cost_base = ucb where id = ln.id;
    -- price jump against the last posted bill of this item (before this one)
    if pb.kind = 'bill' and pct is not null then
      select pl.unit_cost_base into last_c from public.purchase_lines pl join public.purchase_bills x on x.id = pl.bill_id
        where pl.item_id = ln.item_id and x.status = 'posted' and x.kind = 'bill' and x.id <> pb.id and pl.unit_cost_base is not null order by x.posted_at desc, pl.id desc limit 1;
      if last_c is not null and last_c > 0 and abs(ucb - last_c) / last_c * 100 > pct and not jumped then
        jumped := true; nm := it.name_bn;
        perform public._stock_exc(pb.location_id, 'purchase_price_jump', 'yellow',
          nm || ': ক্রয়মূল্য আগের চেয়ে ' || round((ucb - last_c) / last_c * 100, 1)::text || '% বদলেছে (বিল ' || coalesce(pb.bill_no, '-') || ')',
          coalesce(it.name_en, nm) || ': unit cost moved ' || round((ucb - last_c) / last_c * 100, 1)::text || '% from the last purchase (bill ' || coalesce(pb.bill_no, '-') || ')', null, pb.bill_date, 'PURCHASE');
      end if;
    end if;
    if it.tracked then
      if pb.kind = 'bill' then
        perform public.stock_post(ln.item_id, pb.location_id, bq, 'purchase_in', 'purchase', pb.id::text, round(ucb * net, 6), null, now(), null, null, 'none');
      else
        perform public.stock_post(ln.item_id, pb.location_id, -bq, 'purchase_return', 'purchase', pb.id::text, round(ucb * net, 6), null, now(), null, null, 'full');
      end if;
    end if;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_payments is not null and jsonb_typeof(p_payments) = 'array' and jsonb_array_length(p_payments) > 0 then
    if pb.kind <> 'bill' then raise exception 'no_payment_on_return'; end if;
    if not (public.has_grant('supplier_pay', pb.location_id) or public.use_emergency('supplier_pay', pb.location_id, 'post_purchase:' || p_id::text, null, null)) then raise exception 'not allowed'; end if;
    for pay in select * from jsonb_array_elements(p_payments) loop
      pm := pay->>'mode'; amt := nullif(pay->>'amount', '')::numeric;
      if pm is null or pm not in ('cash', 'mobile', 'card', 'bank') then raise exception 'bad_mode'; end if;
      if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
      amt := round(amt, 2); psum := psum + amt;
      insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, created_by, created_staff)
        values (pb.supplier_id, pb.location_id, pb.id, pm, left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), amt, auth.uid(), sid);
    end loop;
    if psum > pb.total then raise exception 'overpaid'; end if;
  end if;
  update public.purchase_bills set status = 'posted', paid = psum, posted_by = auth.uid(), posted_at = now() where id = pb.id;
  return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'paid', psum, 'due', pb.total - psum);
end $$;

-- void a posted purchase: reversing ledger rows, and the payments made with it are voided. A draft can be cancelled by its writer.
create or replace function public.void_purchase(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills; r public.stock_ledger;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into pb from public.purchase_bills where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
  if pb.status = 'void' then return jsonb_build_object('id', pb.id, 'status', 'void', 'dup', true); end if;
  if pb.status = 'draft' then
    if not (public.has_grant(case pb.kind when 'return' then 'purchase_return' else 'purchase_entry' end, pb.location_id)) then raise exception 'not allowed'; end if;
    update public.purchase_bills set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = pb.id;
    return jsonb_build_object('id', pb.id, 'status', 'void');
  end if;
  if not (public.has_grant('purchase_void', pb.location_id) or public.use_emergency('purchase_void', pb.location_id, 'void_purchase:' || p_id::text, pb.total, null)) then raise exception 'not allowed'; end if;
  perform public.lock_check(pb.bill_date);
  for r in select * from public.stock_ledger o where o.ref_type = 'purchase' and o.ref_id = pb.id::text and o.reason in ('purchase_in', 'purchase_return')
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'reversal', 'purchase', pb.id::text, r.unit_cost, r.batch_id, now(), left('void: ' || btrim(p_note), 200), r.id, 'soft');
  end loop;
  update public.supplier_payments set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid() where bill_id = pb.id and not voided;
  update public.purchase_bills set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = pb.id;
  perform public._stock_exc(pb.location_id, 'purchase_void', 'yellow', 'ক্রয় বিল বাতিল: ' || left(btrim(p_note), 100), 'A posted purchase was voided: ' || left(btrim(p_note), 100), null, pb.bill_date, 'PURCHASE', pb.total);
  return jsonb_build_object('id', pb.id, 'status', 'void');
end $$;

-- pay a supplier: one or more payments, allocated to the oldest open bills. Not more than the balance.
create or replace function public.pay_supplier(p_supplier uuid, p_loc int, p_payments jsonb, p_client uuid default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  perform 1 from public.suppliers where id = p_supplier for update;           -- one payment at a time per supplier
  if not found then raise exception 'supplier_not_found'; end if;
  if p_client is not null and exists (select 1 from public.supplier_payments where client_id = p_client) then
    return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier));
  end if;
  if p_payments is null or jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) = 0 then raise exception 'no_payments'; end if;
  for pay in select * from jsonb_array_elements(p_payments) loop
    pm := pay->>'mode'; amt := nullif(pay->>'amount', '')::numeric;
    if pm is null or pm not in ('cash', 'mobile', 'card', 'bank') then raise exception 'bad_mode'; end if;
    if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
    tot := tot + round(amt, 2);
  end loop;
  if not (public.has_grant('supplier_pay', p_loc) or public.use_emergency('supplier_pay', p_loc, 'pay_supplier:' || p_supplier::text, tot, null)) then raise exception 'not allowed'; end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  bal := public._sup_balance(p_supplier);
  if tot > bal then raise exception 'overpaid'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  for pay in select * from jsonb_array_elements(p_payments) loop
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (p_supplier, p_loc, null, pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2), left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client);
  end loop;
  return jsonb_build_object('paid', tot, 'balance', bal - tot);
end $$;

-- reverse a supplier payment made by mistake
create or replace function public.void_supplier_payment(p_id bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare p public.supplier_payments;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into p from public.supplier_payments where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(p.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.has_grant('purchase_void', p.location_id) or public.use_emergency('purchase_void', p.location_id, 'void_payment:' || p_id::text, p.amount, null)) then raise exception 'not allowed'; end if;
  if p.voided then raise exception 'already void'; end if;
  if p.bill_id is not null then raise exception 'void_the_bill'; end if;     -- a payment made with a bill goes with the bill
  perform public.lock_check((p.paid_at at time zone 'Asia/Dhaka')::date);
  update public.supplier_payments set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid() where id = p_id;
  perform public._stock_exc(p.location_id, 'supplier_payment_void', 'yellow', 'সাপ্লায়ার পেমেন্ট বাতিল: ' || left(btrim(p_note), 100), 'A supplier payment was reversed: ' || left(btrim(p_note), 100), null, null, 'PURCHASE', p.amount);
end $$;

-- who we owe, since when. p_loc null = whole company (management / owner), else only the open amount of that location's bills.
create or replace function public.supplier_dues(p_loc int default null)
returns table (supplier_id uuid, name text, mobile text, type_code text, credit_days int, balance numeric, oldest date, overdue numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public._pur_ok(p_loc) then raise exception 'not allowed'; end if;
  return query
    select s.id, s.name, s.mobile, s.type_code, s.credit_days, sum(o.open_amt), min(o.bill_date),
           coalesce(sum(o.open_amt) filter (where s.credit_days is not null and o.bill_date is not null and o.bill_date + s.credit_days < (now() at time zone 'Asia/Dhaka')::date), 0)
    from public._sup_open(null) o join public.suppliers s on s.id = o.supplier_id
    where o.open_amt > 0 and (p_loc is null or o.location_id = p_loc)
    group by s.id, s.name, s.mobile, s.type_code, s.credit_days
    order by 6 desc;
end $$;

-- open bills of one supplier (after the oldest-first allocation)
create or replace function public.supplier_open_bills(p_supplier uuid, p_loc int default null)
returns table (bill_id uuid, bill_no text, bill_date date, location_id int, bill_due numeric, open_amt numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public._pur_ok(p_loc) then raise exception 'not allowed'; end if;
  return query select o.bill_id, o.bill_no, o.bill_date, o.location_id, o.rem, o.open_amt from public._sup_open(p_supplier) o
    where o.open_amt > 0 and (p_loc is null or o.location_id = p_loc) order by o.bill_date nulls first, o.bill_id;
end $$;

-- the supplier's running account (debit = bill, credit = payment / return)
create or replace function public.supplier_ledger(p_supplier uuid, p_loc int default null)
returns table (at timestamptz, kind text, ref text, location_id int, debit numeric, credit numeric, balance numeric, note text, pid bigint, bill_id uuid)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public._pur_ok(p_loc) then raise exception 'not allowed'; end if;
  return query
    with e as (
      select '-infinity'::timestamptz at, 'opening'::text kind, null::text ref, null::int location_id, greatest(s.opening_balance, 0) debit, greatest(-s.opening_balance, 0) credit, null::text note, null::bigint pid, null::uuid bill_id, 0 srt
        from public.suppliers s where s.id = p_supplier and p_loc is null and coalesce(s.opening_balance, 0) <> 0
      union all
      select (b.bill_date::timestamp at time zone 'Asia/Dhaka'), case b.kind when 'bill' then 'bill' else 'return' end, coalesce(b.bill_no, '-'), b.location_id,
             case when b.kind = 'bill' then b.total else 0 end, case when b.kind = 'return' then b.total else 0 end, b.note, null::bigint, b.id, 1
        from public.purchase_bills b where b.supplier_id = p_supplier and b.status = 'posted' and (p_loc is null or b.location_id = p_loc)
      union all
      select p.paid_at, case when p.bill_id is null then 'payment' else 'paid' end, coalesce(p.wallet, p.mode), p.location_id, 0, p.amount, p.note, p.id, p.bill_id, 2
        from public.supplier_payments p where p.supplier_id = p_supplier and not p.voided and (p_loc is null or p.location_id = p_loc))
    select e.at, e.kind, e.ref, e.location_id, e.debit, e.credit, sum(e.debit - e.credit) over (order by e.at, e.srt, e.pid, e.bill_id), e.note, e.pid, e.bill_id
    from e order by e.at, e.srt, e.pid, e.bill_id;
end $$;

-- the payables on one screen (p_loc null = whole company)
create or replace function public.payables_summary(p_loc int default null)
returns table (total_payable numeric, suppliers_owed int, overdue numeric, overdue_suppliers int, oldest date, credit_total numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public._pur_ok(p_loc) then raise exception 'not allowed'; end if;
  return query
    with d as (select * from public.supplier_dues(p_loc)),
    c as (select coalesce(sum(-b), 0) credit from (select public._sup_balance(s.id) b from public.suppliers s) z where p_loc is null and b < 0)
    select coalesce((select sum(d.balance) from d), 0), (select count(*)::int from d), coalesce((select sum(d.overdue) from d), 0),
           (select count(*)::int from d where d.overdue > 0), (select min(d.oldest) from d), (select c.credit from c);
end $$;

-- lists for the screens
create or replace function public.purchase_list(p_loc int default null, p_from date default null, p_to date default null, p_supplier uuid default null, p_status text default null, p_limit int default 100)
returns table (id uuid, kind text, supplier_id uuid, supplier_name text, bill_no text, bill_date date, location_id int, status text, total numeric, discount numeric, paid numeric, due numeric, photo text, created_staff text, n_lines bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public._pur_ok(p_loc) then raise exception 'not allowed'; end if;
  return query
    select b.id, b.kind, b.supplier_id, s.name, b.bill_no, b.bill_date, b.location_id, b.status, b.total, b.discount, b.paid, b.due, b.photo, b.created_staff,
           (select count(*) from public.purchase_lines l where l.bill_id = b.id)
    from public.purchase_bills b join public.suppliers s on s.id = b.supplier_id
    where (p_loc is null or b.location_id = p_loc) and public.can_loc(b.location_id)
      and (p_from is null or b.bill_date >= p_from) and (p_to is null or b.bill_date <= p_to)
      and (p_supplier is null or b.supplier_id = p_supplier) and (p_status is null or b.status = p_status)
    order by b.bill_date desc, b.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 500);
end $$;

create or replace function public.purchase_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare b public.purchase_bills;
begin
  select * into b from public.purchase_bills where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public._pur_ok(b.location_id) then raise exception 'not allowed'; end if;
  return to_jsonb(b) || jsonb_build_object('supplier_name', (select name from public.suppliers where id = b.supplier_id),
    'lines', coalesce((select jsonb_agg(to_jsonb(l) order by l.line_no) from public.purchase_lines l where l.bill_id = b.id), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'mode', p.mode, 'wallet', p.wallet, 'ref', p.ref, 'amount', p.amount, 'paid_at', p.paid_at, 'voided', p.voided) order by p.id) from public.supplier_payments p where p.bill_id = b.id), '[]'::jsonb));
end $$;

-- ---------- (i) security: RLS everywhere, no direct writes, cost columns not granted ----------
alter table public.stock_batches enable row level security;
alter table public.stock_ledger enable row level security;
alter table public.stock_balance enable row level security;
alter table public.stock_wastage enable row level security;
alter table public.stock_transfers enable row level security;
alter table public.purchase_bills enable row level security;
alter table public.purchase_lines enable row level security;
alter table public.supplier_payments enable row level security;

drop policy if exists stock_batches_read on public.stock_batches;
create policy stock_batches_read on public.stock_batches for select to authenticated using (public.can_loc(location_id));
drop policy if exists stock_ledger_read on public.stock_ledger;
create policy stock_ledger_read on public.stock_ledger for select to authenticated using (public.can_loc(location_id));
drop policy if exists stock_balance_read on public.stock_balance;
create policy stock_balance_read on public.stock_balance for select to authenticated using (public.can_loc(location_id));
drop policy if exists stock_wastage_read on public.stock_wastage;
create policy stock_wastage_read on public.stock_wastage for select to authenticated using (public.can_loc(location_id));
drop policy if exists stock_transfers_read on public.stock_transfers;
create policy stock_transfers_read on public.stock_transfers for select to authenticated using (public.can_loc(from_location_id) or public.can_loc(to_location_id));
drop policy if exists purchase_bills_read on public.purchase_bills;
create policy purchase_bills_read on public.purchase_bills for select to authenticated using (public._pur_ok(location_id));
drop policy if exists purchase_lines_read on public.purchase_lines;
create policy purchase_lines_read on public.purchase_lines for select to authenticated
  using (exists (select 1 from public.purchase_bills b where b.id = bill_id and public._pur_ok(b.location_id)));
drop policy if exists supplier_payments_read on public.supplier_payments;
create policy supplier_payments_read on public.supplier_payments for select to authenticated using (public._pur_ok(location_id));

revoke all on public.stock_batches, public.stock_ledger, public.stock_balance, public.stock_wastage, public.stock_transfers,
  public.purchase_bills, public.purchase_lines, public.supplier_payments from public, anon, authenticated;
revoke all on sequence public.stock_batches_id_seq, public.stock_ledger_id_seq, public.purchase_lines_id_seq, public.supplier_payments_id_seq from public, anon, authenticated;
grant select on public.stock_batches, public.stock_wastage, public.stock_transfers, public.purchase_bills, public.purchase_lines, public.supplier_payments to authenticated;
-- the cost columns (unit_cost, avg_cost) are left out of the column grants on purpose
grant select (id, item_id, location_id, qty_delta, reason, ref_type, ref_id, batch_id, reverses_id, made_at, note, created_by, created_at) on public.stock_ledger to authenticated;
grant select (item_id, location_id, qty, updated_at) on public.stock_balance to authenticated;
-- purchase_lines.unit_cost / amount and the bill totals ARE costs; the policies above already limit them to holders of the purchase / cost grants

-- functions: closed to everyone first, then opened to signed-in users only (anon and public get nothing). Internal helpers stay closed.
revoke all on function public._all_locs(), public._may(text, int, text, numeric), public._cost_ok(int), public._pur_ok(int), public._item_base(uuid),
  public._base_qty(uuid, numeric, text), public._unit_factor_base(uuid, text), public._avg_next(numeric, numeric, numeric, numeric, text),
  public._stock_exc(int, text, text, text, text, uuid, date, text, numeric), public._ledger_immutable(), public._ledger_to_balance(),
  public.stock_post(uuid, int, numeric, text, text, text, numeric, bigint, timestamptz, text, bigint, text, uuid, uuid),
  public._sale_stock_out(), public._sale_stock_void(), public._stock_guard(uuid, int, text, date),
  public._sup_open(uuid), public._sup_balance(uuid),
  public.stock_opening(uuid, int, numeric, numeric, text, text, uuid), public.stock_wastage(uuid, int, numeric, text, text, text, text, uuid, bigint),
  public.stock_expire_batch(bigint, text, text, text), public.stock_count_adjust(uuid, int, numeric, text, text, uuid),
  public.stock_issue(uuid, int, numeric, text, text, uuid), public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric),
  public.stock_transfer(int, int, uuid, numeric, text, text, uuid), public.stock_receive_transfer(uuid, numeric, text), public.stock_cancel_transfer(uuid, text),
  public.stock_levels(int, jsonb), public.stock_avg_cost(uuid, int), public.stock_ledger_rows(int, uuid, date, date, int), public.stock_in_transit(int),
  public.expiry_list(int, numeric), public.stock_valuation(int), public.stock_reconcile(boolean),
  public.save_purchase(uuid, uuid, uuid, int, text, date, jsonb, numeric, text, text, text, uuid, text), public.post_purchase(uuid, jsonb), public.void_purchase(uuid, text),
  public.pay_supplier(uuid, int, jsonb, uuid, text), public.void_supplier_payment(bigint, text),
  public.supplier_dues(int), public.supplier_open_bills(uuid, int), public.supplier_ledger(uuid, int), public.payables_summary(int),
  public.purchase_list(int, date, date, uuid, text, int), public.purchase_get(uuid) from public, anon, authenticated;

grant execute on function public._all_locs(), public._cost_ok(int), public._pur_ok(int),                       -- used inside the read policies
  public.stock_opening(uuid, int, numeric, numeric, text, text, uuid), public.stock_wastage(uuid, int, numeric, text, text, text, text, uuid, bigint),
  public.stock_expire_batch(bigint, text, text, text), public.stock_count_adjust(uuid, int, numeric, text, text, uuid),
  public.stock_issue(uuid, int, numeric, text, text, uuid), public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric),
  public.stock_transfer(int, int, uuid, numeric, text, text, uuid), public.stock_receive_transfer(uuid, numeric, text), public.stock_cancel_transfer(uuid, text),
  public.stock_levels(int, jsonb), public.stock_avg_cost(uuid, int), public.stock_ledger_rows(int, uuid, date, date, int), public.stock_in_transit(int),
  public.expiry_list(int, numeric), public.stock_valuation(int), public.stock_reconcile(boolean),
  public.save_purchase(uuid, uuid, uuid, int, text, date, jsonb, numeric, text, text, text, uuid, text), public.post_purchase(uuid, jsonb), public.void_purchase(uuid, text),
  public.pay_supplier(uuid, int, jsonb, uuid, text), public.void_supplier_payment(bigint, text),
  public.supplier_dues(int), public.supplier_open_bills(uuid, int), public.supplier_ledger(uuid, int), public.payables_summary(int),
  public.purchase_list(int, date, date, uuid, text, int), public.purchase_get(uuid) to authenticated;

notify pgrst, 'reload schema';
