-- ============================================================
-- PHASE 40 (Module A: Accounting). Additive and idempotent (paste twice = no error). Needs phase8..phase28.
--   * coa_accounts: chart of accounts (code immutable, never deleted, retire with active = false). Seeded with a bakery / sweets-shop chart.
--   * journal_entries + journal_lines: double-entry journal. Append-only (a correction is a reversing entry). debit = credit, > 0, each line debit XOR credit.
--   * acct_mappings: payment mode / event -> account (the owner can re-point them).
--   * acct_post_pending(dry): reads the business tables (sales, returns, collections, purchases, supplier payments / refunds, 10-2 expense vouchers,
--     cash moves, wastage, production runs) and posts what has no journal entry yet. It never touches the hot paths. Idempotent by (source_type, source_id).
--     A voided source gets a reversing entry. COGS only where a real unit cost exists in the stock ledger - nothing is guessed (flag cogs_missing).
--   * Reports (jsonb): acct_trial_balance, acct_ledger, acct_journal_book, acct_income_statement, acct_balance_sheet, acct_cash_flow, acct_party_ledger, acct_reconcile.
--   * Manual journal acct_journal_post / acct_journal_reverse, opening balances acct_opening, acct_set_start.
--   * Rules: accounting_on (OFF), accounting_autopost (ON), accounting_start_date (empty = "Data needed"). Grants: accounts_view, accounts_manage.
-- Nothing is deleted. Staff-advance / salary postings are not connected (those tables do not exist yet): use the manual journal until they do.
-- ============================================================

-- ---------- rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('accounting_on', 'books', 'switch', 'false', null, null, null, null, 'হিসাবরক্ষণ (খতিয়ান) চালু', 'Accounting (ledger) চালু', 'Accounting (double-entry books) on',
  'চালু করার আগে হিসাব শুরুর তারিখ ও শুরুর জের দিন। বন্ধ থাকলে কিছু পোস্ট হয় না।', 'Set the start date and opening balances first. While off nothing is posted to the books.', 90),
 ('accounting_autopost', 'books', 'switch', 'true', null, null, null, null, 'হিসাব পাতা খুললে নিজে পোস্ট', 'Accounts পাতা খুললে নিজে post', 'Post new business events when the accounts page opens',
  'চালু = হিসাব পাতা খুললে নতুন বিক্রি/কেনা/খরচ নিজে খতিয়ানে উঠে যায়। বন্ধ = "এখন পোস্ট করুন" বোতাম চাপতে হবে।', 'On = opening the accounts page posts new sales, purchases and expenses by itself. Off = press "Post now".', 91)
 on conflict (key) do nothing;
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('accounting_start_date', 'books', 'text', null, 'YYYY-MM-DD', null, null, null, 'হিসাব শুরুর তারিখ', 'হিসাব শুরুর date', 'Accounting start date',
  'এই তারিখের আগের কিছু খতিয়ানে ওঠে না। ফাঁকা = "ডেটা লাগবে"। যেমন 2026-11-01।', 'Nothing dated before this goes into the books. Empty = "Data needed". e.g. 2026-11-01.', 92)
 on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'accounts_view', 'cash', 70, 'হিসাব দেখা (খতিয়ান, ব্যালান্স শিট)', 'Accounts দেখা (ledger, balance sheet)', 'View the accounts (ledger, trial balance, balance sheet, P&L)', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'accounts_view');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'accounts_manage', 'cash', 71, 'হিসাব পরিচালনা (পোস্ট, জার্নাল, হিসাবের তালিকা)', 'Accounts manage (post, journal, chart)', 'Manage the accounts (post, manual journal, opening balances, chart of accounts)', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'accounts_manage');

-- ---------- tables ----------
create table if not exists public.coa_accounts (
  id bigserial primary key,
  code text not null unique check (code ~ '^[0-9A-Za-z.\-]{1,12}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 120),
  name_en text not null check (length(btrim(name_en)) between 1 and 120),
  type text not null check (type in ('asset', 'liability', 'equity', 'income', 'expense')),
  parent_id bigint references public.coa_accounts(id),
  normal_side text not null check (normal_side in ('debit', 'credit')),
  is_group boolean not null default false,            -- a header: it adds up its children, nothing is posted to it
  is_system boolean not null default false,
  active boolean not null default true,
  sort int not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid
);
create index if not exists coa_parent on public.coa_accounts (parent_id);

create table if not exists public.acct_mappings (
  key text primary key check (key ~ '^[a-z0-9_]{2,48}$'),
  account_id bigint not null references public.coa_accounts(id),
  label_bn text, label_en text,
  updated_by uuid, updated_at timestamptz not null default now()
);

create table if not exists public.journal_entries (
  id bigint generated always as identity primary key,
  entry_date date not null,
  location_id int references public.locations(id),
  source_type text not null check (length(source_type) between 1 and 40),
  source_id text not null check (length(source_id) between 1 and 80),
  subtype text,
  memo text not null check (length(memo) <= 300),
  status text not null default 'posted' check (status in ('posted', 'void')),
  reverses_id bigint references public.journal_entries(id),
  flags text,                                          -- e.g. cogs_missing, unreadable_lines
  photo text,
  created_by uuid, created_staff text,
  created_at timestamptz not null default now(),
  client_id uuid unique
);
create unique index if not exists je_source_uq on public.journal_entries (source_type, source_id) where reverses_id is null;
create unique index if not exists je_reverses_uq on public.journal_entries (reverses_id) where reverses_id is not null;
create index if not exists je_date on public.journal_entries (entry_date);

create table if not exists public.journal_lines (
  entry_id bigint not null references public.journal_entries(id),
  line_no int not null,
  account_id bigint not null references public.coa_accounts(id),
  debit numeric not null default 0 check (debit >= 0 and debit <= 1000000000000),
  credit numeric not null default 0 check (credit >= 0 and credit <= 1000000000000),
  location_id int references public.locations(id),
  party_type text check (party_type is null or party_type in ('customer', 'supplier', 'staff', 'partner')),
  party_id text,
  memo text,
  primary key (entry_id, line_no),
  check ((debit > 0) <> (credit > 0))
);
create index if not exists jl_account on public.journal_lines (account_id);
create index if not exists jl_party on public.journal_lines (party_type, party_id) where party_type is not null;

-- ---------- immutability ----------
create or replace function public._acct_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_table_name = 'journal_entries' and tg_op = 'UPDATE' then
    -- the only change ever allowed: an entry becomes 'void' once its reversing entry exists
    if old.status = 'posted' and new.status = 'void' and (to_jsonb(new) - 'status') = (to_jsonb(old) - 'status')
       and exists (select 1 from public.journal_entries r where r.reverses_id = old.id) then return new; end if;
  end if;
  raise exception 'append_only: % is a record, it cannot be changed or deleted (post a reversing entry)', tg_table_name;
end $$;
drop trigger if exists je_ro on public.journal_entries;
create trigger je_ro before update or delete on public.journal_entries for each row execute function public._acct_ro();
drop trigger if exists je_ro_t on public.journal_entries;
create trigger je_ro_t before truncate on public.journal_entries for each statement execute function public._acct_ro();
drop trigger if exists jl_ro on public.journal_lines;
create trigger jl_ro before update or delete on public.journal_lines for each row execute function public._acct_ro();
drop trigger if exists jl_ro_t on public.journal_lines;
create trigger jl_ro_t before truncate on public.journal_lines for each statement execute function public._acct_ro();

create or replace function public._acct_balance_chk() returns trigger language plpgsql security definer set search_path = public as $$
declare d numeric; c numeric;
begin
  select coalesce(sum(debit), 0), coalesce(sum(credit), 0) into d, c from public.journal_lines where entry_id = new.entry_id;
  if d <> c or d <= 0 then raise exception 'unbalanced: debit % credit % (entry %)', d, c, new.entry_id; end if;
  return null;
end $$;
drop trigger if exists jl_balance on public.journal_lines;
create constraint trigger jl_balance after insert on public.journal_lines deferrable initially deferred for each row execute function public._acct_balance_chk();

-- the chart: code, type and side never change; nothing is deleted
create or replace function public._acct_coa_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted – retire instead'; end if;
  if new.code <> old.code or new.type <> old.type or new.normal_side <> old.normal_side or new.is_group <> old.is_group then raise exception 'account_fixed: code, type and side cannot change'; end if;
  return new;
end $$;
drop trigger if exists coa_guard on public.coa_accounts;
create trigger coa_guard before update or delete on public.coa_accounts for each row execute function public._acct_coa_guard();
drop trigger if exists audit_coa_accounts on public.coa_accounts;
create trigger audit_coa_accounts after insert or update on public.coa_accounts for each row execute function public.log_change('id');
drop trigger if exists audit_acct_mappings on public.acct_mappings;
create trigger audit_acct_mappings after insert or update on public.acct_mappings for each row execute function public.log_change('key');
drop trigger if exists acct_mappings_no_delete on public.acct_mappings;
create trigger acct_mappings_no_delete before delete on public.acct_mappings for each row execute function public.no_hard_delete();

-- ---------- access helpers ----------
create or replace function public._acct_view() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('accounts_view') or public.has_grant('accounts_manage')
    or exists (select 1 from public.locations l where public.has_grant('accounts_view', l.id) or public.has_grant('accounts_manage', l.id)));
$$;
create or replace function public._acct_manage() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('accounts_manage')
    or exists (select 1 from public.locations l where public.has_grant('accounts_manage', l.id)));
$$;
-- every place (and the company-level lines with no place): owner, head management, or an accountant whose grant is not tied to one place
create or replace function public._acct_all() returns boolean language sql stable security definer set search_path = public as $$ select public.can_loc(null) or (public.is_active() and public.has_grant('accounts_manage')); $$;
create or replace function public._acct_locs() returns int[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(l.id), '{}') from public.locations l where public.can_loc(l.id);
$$;
create or replace function public._acct_start() returns date language plpgsql stable security definer set search_path = public as $$
declare v text := public.rule_txt('accounting_start_date');
begin
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  begin return v::date; exception when others then return null; end;
end $$;
create or replace function public._acct_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date; $$;
create or replace function public._acct_locked(p_date date) returns boolean language plpgsql security definer set search_path = public as $$
begin perform public.lock_check(p_date); return false; exception when others then return true; end $$;

-- ---------- RLS ----------
alter table public.coa_accounts enable row level security;
alter table public.acct_mappings enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
drop policy if exists coa_read on public.coa_accounts;
create policy coa_read on public.coa_accounts for select to authenticated using (public._acct_view());
drop policy if exists acct_map_read on public.acct_mappings;
create policy acct_map_read on public.acct_mappings for select to authenticated using (public._acct_view());
drop policy if exists je_read on public.journal_entries;
create policy je_read on public.journal_entries for select to authenticated using (public._acct_view() and (public._acct_all() or (location_id is not null and public.can_loc(location_id))));
drop policy if exists jl_read on public.journal_lines;
create policy jl_read on public.journal_lines for select to authenticated using (public._acct_view() and (public._acct_all() or (location_id is not null and public.can_loc(location_id))));
revoke all on public.coa_accounts, public.acct_mappings, public.journal_entries, public.journal_lines from public, anon, authenticated;
grant select on public.coa_accounts, public.acct_mappings, public.journal_entries, public.journal_lines to authenticated;

-- ---------- seed: chart of accounts ----------
do $seed$
declare r record;
begin
  for r in select * from (values
    ('1000', 'সম্পদ', 'Assets', 'asset', 'debit', true, null, 10),
    ('1100', 'নগদ ও ব্যাংক', 'Cash and bank', 'asset', 'debit', true, '1000', 11),
    ('1110', 'হাতে নগদ', 'Cash in hand', 'asset', 'debit', false, '1100', 12),
    ('1120', 'ব্যাংক', 'Bank', 'asset', 'debit', false, '1100', 13),
    ('1130', 'মোবাইল ওয়ালেট (বিকাশ/নগদ)', 'Mobile wallets (bKash / Nagad)', 'asset', 'debit', false, '1100', 14),
    ('1140', 'কার্ডের পাওনা', 'Card receivable', 'asset', 'debit', false, '1100', 15),
    ('1200', 'পাওনা ও অগ্রিম', 'Receivables and advances', 'asset', 'debit', true, '1000', 20),
    ('1210', 'গ্রাহকের বাকি', 'Customer receivables', 'asset', 'debit', false, '1200', 21),
    ('1220', 'স্টাফকে অগ্রিম', 'Advances to staff', 'asset', 'debit', false, '1200', 22),
    ('1230', 'লোকেশনের মধ্যে লেনদেন (ক্লিয়ারিং)', 'Inter-location clearing', 'asset', 'debit', false, '1200', 23),
    ('1300', 'মজুত মাল', 'Inventory', 'asset', 'debit', true, '1000', 30),
    ('1310', 'মজুত: তৈরি পণ্য', 'Inventory: finished goods', 'asset', 'debit', false, '1300', 31),
    ('1320', 'মজুত: কাঁচামাল', 'Inventory: raw materials', 'asset', 'debit', false, '1300', 32),
    ('1330', 'মজুত: প্যাকেজিং', 'Inventory: packaging', 'asset', 'debit', false, '1300', 33),
    ('1400', 'অগ্রিম দেওয়া খরচ', 'Prepaid expenses', 'asset', 'debit', false, '1000', 40),
    ('1500', 'স্থায়ী সম্পদ', 'Fixed assets', 'asset', 'debit', true, '1000', 50),
    ('1510', 'স্থায়ী সম্পদ (কেনা দামে)', 'Fixed assets at cost', 'asset', 'debit', false, '1500', 51),
    ('1590', 'সঞ্চিত অবচয় (বিয়োগ)', 'Accumulated depreciation (contra)', 'asset', 'credit', false, '1500', 52),
    ('2000', 'দায়', 'Liabilities', 'liability', 'credit', true, null, 100),
    ('2100', 'সরবরাহকারীর পাওনা', 'Supplier payables', 'liability', 'credit', false, '2000', 101),
    ('2200', 'বকেয়া বেতন', 'Accrued salaries', 'liability', 'credit', false, '2000', 102),
    ('2300', 'গ্রাহকের অগ্রিম (আমাদের দায়)', 'Customer advances (liability)', 'liability', 'credit', false, '2000', 103),
    ('2400', 'অন্যান্য বকেয়া খরচ', 'Other accrued expenses', 'liability', 'credit', false, '2000', 104),
    ('3000', 'মালিকানা', 'Equity', 'equity', 'credit', true, null, 200),
    ('3100', 'মালিকের মূলধন', 'Owner capital', 'equity', 'credit', false, '3000', 201),
    ('3200', 'অংশীদার / বিনিয়োগকারীর মূলধন', 'Partner / investor capital', 'equity', 'credit', false, '3000', 202),
    ('3300', 'মালিকের উত্তোলন (বিয়োগ)', 'Owner drawings (contra)', 'equity', 'debit', false, '3000', 203),
    ('3900', 'জমা মুনাফা (শুরুর)', 'Retained earnings (opening)', 'equity', 'credit', false, '3000', 209),
    ('4000', 'আয়', 'Income', 'income', 'credit', true, null, 300),
    ('4100', 'বিক্রয়', 'Sales', 'income', 'credit', false, '4000', 301),
    ('4110', 'বিক্রি ফেরত (বিয়োগ)', 'Sales returns (contra)', 'income', 'debit', false, '4000', 302),
    ('4120', 'বিক্রয় ছাড় / ডিসকাউন্ট (বিয়োগ)', 'Sales discounts (contra)', 'income', 'debit', false, '4000', 303),
    ('4900', 'অন্যান্য আয়', 'Other income', 'income', 'credit', false, '4000', 309),
    ('5000', 'বিক্রীত পণ্যের খরচ (COGS)', 'Cost of goods sold', 'expense', 'debit', false, null, 400),
    ('5100', 'নষ্ট মালের ক্ষতি', 'Wastage loss', 'expense', 'debit', false, null, 401),
    ('5200', 'বেতন ও মজুরি', 'Salaries and wages', 'expense', 'debit', false, null, 402),
    ('5300', 'ভাড়া', 'Rent', 'expense', 'debit', false, null, 403),
    ('5400', 'বিদ্যুৎ, পানি, গ্যাস', 'Utilities', 'expense', 'debit', false, null, 404),
    ('5500', 'মার্কেটিং', 'Marketing', 'expense', 'debit', false, null, 405),
    ('5600', 'মেরামত ও রক্ষণাবেক্ষণ', 'Repairs and maintenance', 'expense', 'debit', false, null, 406),
    ('5700', 'যাতায়াত ও পরিবহন', 'Transport', 'expense', 'debit', false, null, 407),
    ('5800', 'ক্যাশ ঘাটতি / উদ্বৃত্ত', 'Cash short / over', 'expense', 'debit', false, null, 408),
    ('5810', 'ব্যাংক চার্জ', 'Bank charges', 'expense', 'debit', false, null, 409),
    ('5820', 'অবচয়', 'Depreciation', 'expense', 'debit', false, null, 410),
    ('5830', 'স্টাফের খাবার ও নাস্তা', 'Staff meals and welfare', 'expense', 'debit', false, null, 411),
    ('5840', 'আপ্যায়ন', 'Hospitality', 'expense', 'debit', false, null, 412),
    ('5850', 'বাইরে থেকে কেনা মাল', 'Outside-sourced goods', 'expense', 'debit', false, null, 413),
    ('5860', 'ভোগ্য সামগ্রী', 'Consumables', 'expense', 'debit', false, null, 414),
    ('5870', 'অশ্রেণীবদ্ধ ক্রয়', 'Purchases not classified', 'expense', 'debit', false, null, 415),
    ('5900', 'অন্যান্য খরচ', 'Other expenses', 'expense', 'debit', false, null, 499)
  ) as v(code, nb, ne, ty, sd, grp, par, srt) loop
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort)
      values (r.code, r.nb, r.ne, r.ty, r.sd, r.grp, true, r.srt) on conflict (code) do nothing;
    if r.par is not null then
      update public.coa_accounts c set parent_id = (select p.id from public.coa_accounts p where p.code = r.par) where c.code = r.code and c.parent_id is null and c.is_system;
    end if;
  end loop;
end $seed$;

insert into public.acct_mappings (key, account_id, label_bn, label_en)
select v.k, a.id, v.lb, v.le from (values
  ('pay_cash', '1110', 'নগদ টাকা', 'Cash payments'),
  ('pay_bank', '1120', 'ব্যাংক / কার্ডে সরবরাহকারীকে', 'Bank payments'),
  ('pay_mobile', '1130', 'মোবাইল ওয়ালেট', 'Mobile wallet payments'),
  ('pay_card', '1140', 'কার্ডে বিক্রি (পাওনা)', 'Card sales (receivable)'),
  ('sales', '4100', 'বিক্রয় আয়', 'Sales revenue'),
  ('sales_returns', '4110', 'বিক্রি ফেরত', 'Sales returns'),
  ('sales_discount', '4120', 'বিক্রয়ে ছাড়', 'Sales discounts'),
  ('receivable', '1210', 'গ্রাহকের বাকি', 'Customer receivable'),
  ('payable', '2100', 'সরবরাহকারীর পাওনা', 'Supplier payable'),
  ('cust_advance', '2300', 'গ্রাহকের অগ্রিম', 'Customer advance'),
  ('inv_finished', '1310', 'তৈরি পণ্যের মজুত', 'Finished goods inventory'),
  ('inv_raw', '1320', 'কাঁচামালের মজুত', 'Raw materials inventory'),
  ('inv_pack', '1330', 'প্যাকেজিংয়ের মজুত', 'Packaging inventory'),
  ('cogs', '5000', 'বিক্রীত পণ্যের খরচ', 'Cost of goods sold'),
  ('wastage', '5100', 'নষ্ট মালের ক্ষতি', 'Wastage loss'),
  ('owner_capital', '3100', 'মালিকের টাকা ঢোকানো', 'Owner top-up'),
  ('owner_drawings', '3300', 'মালিকের উত্তোলন', 'Owner draw'),
  ('hub_clearing', '1230', 'হাব থেকে প্রাপ্ত নগদ', 'Hub receipts clearing'),
  ('fixed_assets', '1510', 'স্থায়ী সম্পদ কেনা', 'Fixed asset purchases'),
  ('purch_consumable', '5860', 'ভোগ্য সামগ্রী কেনা', 'Consumable purchases'),
  ('purch_unclassified', '5870', 'আইটেম ছাড়া ক্রয়', 'Purchases without an item'),
  ('retained', '3900', 'শুরুর জমা মুনাফা (ব্যালান্স মেলাতে)', 'Opening retained earnings (balancing)'),
  ('exp_staff_meal', '5830', '10-2: স্টাফের খাবার', '10-2 staff meals'),
  ('exp_transport', '5700', '10-2: যাতায়াত', '10-2 transport'),
  ('exp_hospitality', '5840', '10-2: আপ্যায়ন', '10-2 hospitality'),
  ('exp_repair', '5600', '10-2: মেরামত / ইউটিলিটি', '10-2 repairs / utilities'),
  ('exp_labour', '5200', '10-2: অস্থায়ী শ্রমিক', '10-2 temporary labour'),
  ('exp_sourcing', '5850', '10-2: বাইরের মাল', '10-2 outside-sourced goods'),
  ('exp_other', '5900', '10-2: অন্যান্য খরচ (যে খাতের আলাদা হিসাব নেই)', '10-2 other expenses (any head without its own mapping)')
) as v(k, c, lb, le) join public.coa_accounts a on a.code = v.c
on conflict (key) do nothing;

-- ---------- internal helpers ----------
create or replace function public._acct_num(t text) returns numeric language sql immutable set search_path = public as $$
  select case when translate(btrim(t), '০১২৩৪৫৬৭৮৯,', '0123456789') ~ '^[0-9]{1,12}(\.[0-9]{1,4})?$' then translate(btrim(t), '০১২৩৪৫৬৭৮৯,', '0123456789')::numeric end;
$$;
create or replace function public._acct_inv_key(t text) returns text language sql immutable as $$
  select case coalesce(t, '') when 'raw_material' then 'inv_raw' when 'packaging' then 'inv_pack' else 'inv_finished' end;
$$;
create or replace function public._acct_buy_key(t text) returns text language sql immutable as $$
  select case coalesce(t, '-') when '-' then 'purch_unclassified' when 'finished_good' then 'inv_finished' when 'resale' then 'inv_finished'
    when 'raw_material' then 'inv_raw' when 'packaging' then 'inv_pack' when 'asset' then 'fixed_assets'
    when 'consumable' then 'purch_consumable' when 'infrastructure' then 'purch_consumable' when 'controlled' then 'purch_consumable' else 'inv_raw' end;
$$;
create or replace function public._acct_paykey(p_mode text, p_card_to_bank boolean default false) returns text language sql immutable as $$
  select case p_mode when 'cash' then 'pay_cash' when 'mobile' then 'pay_mobile' when 'bank' then 'pay_bank' when 'card' then case when p_card_to_bank then 'pay_bank' else 'pay_card' end end;
$$;

-- does this source still need an action? (live and not posted yet) or (gone and posted and not reversed yet)
create or replace function public._acct_need(p_type text, p_id text, p_live boolean) returns boolean language sql stable set search_path = public as $$
  select case when p_live then not exists (select 1 from public.journal_entries e where e.source_type = p_type and e.source_id = p_id and e.reverses_id is null)
    else exists (select 1 from public.journal_entries e where e.source_type = p_type and e.source_id = p_id and e.reverses_id is null)
         and not exists (select 1 from public.journal_entries r join public.journal_entries o on o.id = r.reverses_id where o.source_type = p_type and o.source_id = p_id and o.reverses_id is null) end;
$$;

-- bill amount split by what was bought (discount spread over the lines, the last cent goes to the biggest part)
create or replace function public._acct_purchase_alloc(p_bill uuid) returns table(k text, amt numeric) language plpgsql stable set search_path = public as $$
declare b public.purchase_bills; f numeric; ks text[] := '{}'; vs numeric[] := '{}'; r record; sm numeric := 0; big int := 1; i int;
begin
  select * into b from public.purchase_bills where id = p_bill;
  if not found then return; end if;
  f := case when b.subtotal > 0 then (b.subtotal - b.discount) / b.subtotal else 1 end;
  for r in select public._acct_buy_key(it.item_type) key, sum(coalesce(l.amount, l.qty * l.unit_cost, 0)) a
           from public.purchase_lines l left join public.items it on it.id = l.item_id where l.bill_id = p_bill group by 1 order by 1 loop
    ks := ks || r.key; vs := vs || round(r.a * f, 2);
  end loop;
  if coalesce(array_length(ks, 1), 0) = 0 then ks := array['purch_unclassified']; vs := array[b.total]; end if;
  for i in 1 .. array_length(vs, 1) loop sm := sm + vs[i]; if vs[i] > vs[big] then big := i; end if; end loop;
  vs[big] := vs[big] + (b.total - sm);
  for i in 1 .. array_length(ks, 1) loop
    if vs[i] > 0 then k := ks[i]; amt := vs[i]; return next; end if;
  end loop;
end $$;

-- ---------- the scanner: every business document that needs posting or reversing ----------
-- lines are {a: mapping key, d|c: amount, pt, pid, m}. Nothing is posted here.
create or replace function public._acct_docs(p_start date) returns table(
  source_type text, source_id text, entry_date date, location_id int, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
language plpgsql stable security definer set search_path = public as $fn$
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and l.unit_cost is not null)) then 'cogs_missing' end,
    null::text,
    case when s.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode
        union all select 2, jsonb_build_object('a', 'receivable', 'd', round(s.total - pp.paid, 2), 'pt', case when s.customer_id is not null then 'customer' end, 'pid', s.customer_id::text) where s.total - pp.paid > 0.004
        union all select 3, jsonb_build_object('a', 'sales_discount', 'd', s.discount) where s.discount > 0
        union all select 4, jsonb_build_object('a', 'sales', 'c', s.subtotal)
        union all select 5, jsonb_build_object('a', 'cogs', 'd', cg.amt) from (select round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null) cg where cg.amt > 0
        union all select 6, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt) from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) x) end
  from public.sales s cross join lateral (select coalesce(sum(p.amount), 0) paid from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided) pp
  where s.sale_date >= p_start and s.subtotal > 0 and public._acct_need('sale', s.id::text, s.status = 'done');

  -- sale returns
  return query
  select 'sale_return'::text, r.id::text, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, ('Return of receipt ' || coalesce(s.receipt::text, '-'))::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when r.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and l.unit_cost is not null)) then 'cogs_missing' end,
    null::text,
    case when r.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'sales_returns', 'd', r.amount) j
        union all select 2, jsonb_build_object('a', 'receivable', 'c', r.credit_amount, 'pt', case when r.customer_id is not null then 'customer' end, 'pid', r.customer_id::text) where r.credit_amount > 0
        union all select 3, jsonb_build_object('a', public._acct_paykey(coalesce(r.refund_mode, 'cash')), 'c', r.refund_amount) where r.refund_amount > 0
        union all select 4, jsonb_build_object('a', public._acct_inv_key(z.t), 'd', z.amt) from (select it.item_type t, round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
        union all select 5, jsonb_build_object('a', 'cogs', 'c', cg.amt) from (select round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null) cg where cg.amt > 0
      ) x) end
  from public.sale_returns r left join public.sales s on s.id = r.sale_id
  where (r.created_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('sale_return', r.id::text, r.status = 'done');

  -- customer collections (later payments of dues)
  return query
  select 'collection'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Due collection'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(p.mode), 'd', p.amount),
      jsonb_build_object('a', 'receivable', 'c', p.amount, 'pt', case when p.customer_id is not null then 'customer' end, 'pid', p.customer_id::text)) end
  from public.sale_payments p
  where p.kind = 'collection' and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('collection', p.id::text, not p.voided);

  -- purchase bills and purchase returns
  return query
  select 'purchase'::text, b.id::text, b.bill_date, b.location_id, ((case b.kind when 'return' then 'Purchase return ' else 'Purchase bill ' end) || coalesce(b.bill_no, '-'))::text, b.kind, b.status = 'posted' and b.total > 0, (b.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when b.status = 'posted' and b.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'payable', case when b.kind = 'return' then 'd' else 'c' end, b.total, 'pt', 'supplier', 'pid', b.supplier_id::text) j
        union all select 2, jsonb_build_object('a', al.k, case when b.kind = 'return' then 'c' else 'd' end, al.amt) from public._acct_purchase_alloc(b.id) al
      ) x) end
  from public.purchase_bills b
  where b.bill_date >= p_start and public._acct_need('purchase', b.id::text, b.status = 'posted' and b.total > 0);

  -- supplier payments
  return query
  select 'supplier_payment'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Supplier payment'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', 'payable', 'd', p.amount, 'pt', 'supplier', 'pid', p.supplier_id::text),
      jsonb_build_object('a', public._acct_paykey(p.mode, true), 'c', p.amount)) end
  from public.supplier_payments p
  where (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_payment', p.id::text, not p.voided);

  -- supplier refunds
  return query
  select 'supplier_refund'::text, f.id::text, (f.refunded_at at time zone 'Asia/Dhaka')::date, f.location_id, 'Supplier refund'::text, null::text, not f.voided, public._acct_today(), null::text, null::text,
    case when not f.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(f.mode, true), 'd', f.amount),
      jsonb_build_object('a', 'payable', 'c', f.amount, 'pt', 'supplier', 'pid', f.supplier_id::text)) end
  from public.supplier_refunds f
  where (f.refunded_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_refund', f.id::text, not f.voided);

  -- 10-2 expense vouchers (approved; a re-opened or re-numbered voucher is reversed, the new revision posted)
  return query
  select 'expense_voucher'::text, e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.entry_date, e.location_id, ('Expense voucher ' || e.serial)::text, null::text, v.total > 0, public._acct_today(),
    case when v.bad > 0 then 'unreadable_lines' end, null::text,
    case when v.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'exp_' || h.head, 'd', h.amt) j from (
          select regexp_replace(lower(coalesce(nullif(btrim(x->>'head'), ''), 'other')), '[^a-z0-9_]', '_', 'g') head, sum(public._acct_num(x->>'amount')) amt
          from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x
          where public._acct_num(x->>'amount') > 0 group by 1) h
        union all select 2, jsonb_build_object('a', 'pay_cash', 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
           count(*) filter (where coalesce(btrim(x->>'amount'), '') <> '' and public._acct_num(x->>'amount') is null) bad
    from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x) v
  where e.form_code = '10-2' and e.status = 'approved' and e.entry_date >= p_start and public._acct_need('expense_voucher', e.id::text || ':' || coalesce(e.rev_no, 0)::text, v.total > 0);
  return query
  select 'expense_voucher'::text, je.source_id, je.entry_date, je.location_id, 'Expense voucher no longer approved'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'expense_voucher' and je.reverses_id is null
    and not exists (select 1 from public.entries e where e.form_code = '10-2' and e.status = 'approved' and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);

  -- cash moves (bank deposit / withdraw, owner top-up / draw, customer advances, hub receipt)
  return query
  select 'cash_move'::text, m.id::text, m.move_date, m.location_id, ('Cash move: ' || m.kind)::text, m.kind, m.status = 'done', (m.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when m.status = 'done' then case m.kind
      when 'bank_deposit' then jsonb_build_array(jsonb_build_object('a', 'pay_bank', 'd', m.amount), jsonb_build_object('a', 'pay_cash', 'c', m.amount))
      when 'bank_withdraw' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'pay_bank', 'c', m.amount))
      when 'owner_topup' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'owner_capital', 'c', m.amount))
      when 'owner_draw' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', m.amount), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'cust_advance', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'cust_advance_refund' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance_used' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', 'receivable', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'hub_receipt' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'hub_clearing', 'c', m.amount))
    end end
  from public.cash_moves m
  where m.move_date >= p_start and public._acct_need('cash_move', m.id::text, m.status = 'done');

  -- wastage at the real cost in the stock ledger
  return query
  select 'wastage'::text, w.id::text, (w.made_at at time zone 'Asia/Dhaka')::date, w.location_id, 'Wastage written off'::text, null::text, true, null::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when c.amt is null or c.amt <= 0 then 'cost_missing' end,
    case when c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'wastage', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) y) end
  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where l.unit_cost is null) nulls
    from public.stock_ledger l where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) then 'cost_missing' end,
    case when r.status = 'done' and c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) y) end
  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where l.unit_cost is null) nulls
    from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done');
end $fn$;

-- keys -> account ids; accepts {a}, {account_id} or {code}; returns [{account_id, debit, credit, party_type, party_id, memo, location_id}]
create or replace function public._acct_resolve(p_lines jsonb, p_loc int) returns jsonb language plpgsql stable set search_path = public as $$
declare e jsonb; out jsonb := '[]'; aid bigint; k text; d numeric; c numeric; ds text; cs text; lc int; pid text;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then raise exception 'no_lines'; end if;
  for e in select * from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(e) <> 'object' then raise exception 'bad_line'; end if;
    aid := null;
    if nullif(e->>'account_id', '') is not null then
      if (e->>'account_id') !~ '^[0-9]{1,15}$' then raise exception 'unknown_account'; end if;
      aid := (e->>'account_id')::bigint;
      if not exists (select 1 from public.coa_accounts where id = aid) then raise exception 'unknown_account'; end if;
    elsif nullif(e->>'code', '') is not null then
      select id into aid from public.coa_accounts where code = e->>'code';
      if aid is null then raise exception 'unknown_account'; end if;
    elsif nullif(e->>'a', '') is not null then
      k := e->>'a';
      select account_id into aid from public.acct_mappings where key = k;
      if aid is null and k like 'exp\_%' then select account_id into aid from public.acct_mappings where key = 'exp_other'; end if;
      if aid is null then raise exception 'mapping_missing:%', k; end if;
    else raise exception 'unknown_account'; end if;
    ds := coalesce(e->>'debit', e->>'d', '0'); cs := coalesce(e->>'credit', e->>'c', '0');
    if ds = '' then ds := '0'; end if; if cs = '' then cs := '0'; end if;
    if ds !~ '^[0-9]{1,13}(\.[0-9]{1,6})?$' or cs !~ '^[0-9]{1,13}(\.[0-9]{1,6})?$' then raise exception 'bad_amount'; end if;
    d := round(ds::numeric, 2); c := round(cs::numeric, 2);
    lc := coalesce(nullif(e->>'location_id', '')::int, p_loc);
    pid := nullif(btrim(coalesce(e->>'party_id', e->>'pid')), '');
    out := out || jsonb_build_object('account_id', aid, 'debit', d, 'credit', c, 'party_type', nullif(coalesce(e->>'party_type', e->>'pt'), ''), 'party_id', left(pid, 60),
      'memo', left(nullif(btrim(coalesce(e->>'memo', e->>'m')), ''), 200), 'location_id', lc);
  end loop;
  return out;
end $$;

-- the system lines are merged (same account / party twice = one line, debit and credit netted)
create or replace function public._acct_merge(p_lines jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(jsonb_build_object('a', a, 'd', case when net > 0 then net end, 'c', case when net < 0 then -net end, 'pt', pt, 'pid', pid) order by a, pid), '[]'::jsonb)
  from (select e->>'a' a, nullif(e->>'pt', '') pt, nullif(e->>'pid', '') pid, sum(coalesce((e->>'d')::numeric, 0) - coalesce((e->>'c')::numeric, 0)) net
        from jsonb_array_elements(p_lines) e group by 1, 2, 3) z where net <> 0;
$$;

-- the one place that writes a journal entry
create or replace function public._acct_write(p_date date, p_loc int, p_type text, p_sid text, p_subtype text, p_memo text, p_flags text, p_lines jsonb,
  p_reverses bigint default null, p_client uuid default null, p_photo text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare st date := public._acct_start(); id_ bigint; e jsonb; n int := 0; td numeric := 0; tc numeric := 0; d numeric; c numeric; a public.coa_accounts; sid text; pt text; lc int;
begin
  if st is null then raise exception 'data_needed'; end if;
  if p_date is null or p_date < st then raise exception 'before_start'; end if;
  if p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then raise exception 'need_two_lines'; end if;
  if jsonb_array_length(p_lines) > 200 then raise exception 'too_many_lines'; end if;
  if p_photo is not null and (length(p_photo) > 300 or p_photo like '%..%') then raise exception 'bad_photo'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.journal_entries (entry_date, location_id, source_type, source_id, subtype, memo, flags, photo, reverses_id, created_by, created_staff, client_id)
    values (p_date, p_loc, p_type, p_sid, p_subtype, left(coalesce(nullif(btrim(p_memo), ''), p_type), 300), p_flags, nullif(btrim(p_photo), ''), p_reverses, auth.uid(), sid, p_client) returning id into id_;
  for e in select * from jsonb_array_elements(p_lines) loop
    n := n + 1;
    d := (e->>'debit')::numeric; c := (e->>'credit')::numeric; pt := e->>'party_type'; lc := nullif(e->>'location_id', '')::int;
    if d < 0 or c < 0 or (d > 0) = (c > 0) then raise exception 'line_debit_xor_credit'; end if;
    if d > 1000000000000 or c > 1000000000000 then raise exception 'bad_amount'; end if;
    select * into a from public.coa_accounts where id = (e->>'account_id')::bigint;
    if not found then raise exception 'unknown_account'; end if;
    if a.is_group then raise exception 'account_is_group: %', a.code; end if;
    if not a.active and p_reverses is null then raise exception 'account_retired: %', a.code; end if;
    if pt is not null and pt not in ('customer', 'supplier', 'staff', 'partner') then raise exception 'bad_party'; end if;
    if pt is not null and nullif(e->>'party_id', '') is null then raise exception 'party_id_required'; end if;
    if lc is not null and not exists (select 1 from public.locations where id = lc) then raise exception 'bad_location'; end if;
    insert into public.journal_lines (entry_id, line_no, account_id, debit, credit, location_id, party_type, party_id, memo)
      values (id_, n, a.id, d, c, lc, pt, case when pt is not null then left(e->>'party_id', 60) end, left(nullif(e->>'memo', ''), 200));
    td := td + d; tc := tc + c;
  end loop;
  if td <> tc or td <= 0 then raise exception 'unbalanced' using detail = 'debit ' || td::text || ' credit ' || tc::text; end if;
  return id_;
end $$;

create or replace function public._acct_reverse(p_orig bigint, p_date date, p_memo text, p_client uuid default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare o public.journal_entries; id_ bigint; lines jsonb;
begin
  select * into o from public.journal_entries where id = p_orig for update;
  if not found then raise exception 'not found'; end if;
  if o.reverses_id is not null then raise exception 'cannot_reverse_a_reversal'; end if;
  if exists (select 1 from public.journal_entries where reverses_id = p_orig) then raise exception 'already_reversed'; end if;
  select jsonb_agg(jsonb_build_object('account_id', account_id, 'debit', credit, 'credit', debit, 'party_type', party_type, 'party_id', party_id, 'memo', memo, 'location_id', location_id) order by line_no)
    into lines from public.journal_lines where entry_id = p_orig;
  id_ := public._acct_write(greatest(p_date, o.entry_date), o.location_id, o.source_type, o.source_id, o.subtype, 'Reversal: ' || o.memo, o.flags, lines, p_orig, p_client, null);
  update public.journal_entries set status = 'void' where id = p_orig;
  return id_;
end $$;

-- ---------- status / settings ----------
create or replace function public.acct_status() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('accounting_on'), 'autopost', public.rule_on('accounting_autopost'), 'start', public._acct_start(),
    'can_manage', public._acct_manage(), 'owner', public.is_owner(),
    'opening', exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id)),
    'entries', (select count(*) from public.journal_entries), 'accounts', (select count(*) from public.coa_accounts where active),
    'last_post', (select max(created_at) from public.journal_entries where created_by is not null and source_type not in ('manual', 'opening')));
end $$;

create or replace function public.acct_set_start(p_date date) returns jsonb language plpgsql security definer set search_path = public as $$
declare mn date;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_date is null or p_date < date '2000-01-01' or p_date > public._acct_today() + 366 then raise exception 'bad_date'; end if;
  select min(entry_date) into mn from public.journal_entries;
  if mn is not null and p_date > mn then raise exception 'entries_before_start' using detail = mn::text; end if;
  perform public.set_rule('accounting_start_date', to_jsonb(p_date::text));
  return jsonb_build_object('start', p_date);
end $$;

-- ---------- chart of accounts ----------
create or replace function public.acct_account_save(p_id bigint, p_code text, p_name_bn text, p_name_en text, p_type text, p_parent bigint default null,
  p_active boolean default true, p_sort int default null, p_contra boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.coa_accounts; side text; par public.coa_accounts;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_name_bn is null or length(btrim(p_name_bn)) = 0 or length(p_name_bn) > 120 or p_name_en is null or length(btrim(p_name_en)) = 0 or length(p_name_en) > 120 then raise exception 'name_required'; end if;
  if p_parent is not null then
    select * into par from public.coa_accounts where id = p_parent;
    if not found or not par.is_group then raise exception 'bad_parent'; end if;
  end if;
  if p_id is null then
    if p_code is null or p_code !~ '^[0-9A-Za-z.\-]{1,12}$' then raise exception 'bad_code'; end if;
    if p_type is null or p_type not in ('asset', 'liability', 'equity', 'income', 'expense') then raise exception 'bad_type'; end if;
    if par.id is not null and par.type <> p_type then raise exception 'bad_parent'; end if;
    if exists (select 1 from public.coa_accounts where code = p_code) then raise exception 'code_taken'; end if;
    side := case when (p_type in ('asset', 'expense')) <> coalesce(p_contra, false) then 'debit' else 'credit' end;
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, parent_id, sort, created_by)
      values (p_code, btrim(p_name_bn), btrim(p_name_en), p_type, side, p_parent, coalesce(p_sort, 500), auth.uid()) returning * into a;
    return jsonb_build_object('id', a.id, 'code', a.code);
  end if;
  select * into a from public.coa_accounts where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if par.id is not null and (par.type <> a.type or par.id = a.id) then raise exception 'bad_parent'; end if;
  if not coalesce(p_active, true) then
    if a.is_system and exists (select 1 from public.acct_mappings where account_id = a.id) then raise exception 'account_in_use_by_mapping'; end if;
    if exists (select 1 from public.coa_accounts where parent_id = a.id and active) then raise exception 'has_active_children'; end if;
  end if;
  update public.coa_accounts set name_bn = btrim(p_name_bn), name_en = btrim(p_name_en), parent_id = coalesce(p_parent, parent_id), active = coalesce(p_active, active), sort = coalesce(p_sort, sort) where id = a.id;
  return jsonb_build_object('id', a.id, 'code', a.code);
end $$;

create or replace function public.acct_mapping_set(p_key text, p_account bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.coa_accounts;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_key is null or p_key !~ '^[a-z0-9_]{2,48}$' then raise exception 'bad_key'; end if;
  select * into a from public.coa_accounts where id = p_account;
  if not found or a.is_group or not a.active then raise exception 'bad_account'; end if;
  if not exists (select 1 from public.acct_mappings where key = p_key) and p_key not like 'exp\_%' then raise exception 'bad_key'; end if;
  insert into public.acct_mappings (key, account_id, updated_by) values (p_key, p_account, auth.uid())
    on conflict (key) do update set account_id = excluded.account_id, updated_by = auth.uid(), updated_at = now();
  return jsonb_build_object('key', p_key, 'account_id', p_account);
end $$;

-- ---------- posting from the business events ----------
create or replace function public.acct_post_pending(p_dry boolean default false, p_limit int default 1500) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st date := public._acct_start(); d record; n int := 0; posted int := 0; rev int := 0; locked int := 0; more boolean := false; ln jsonb; res jsonb; orig public.journal_entries; rdate date;
        by_type jsonb := '{}'; waiting jsonb := '{}'; errors jsonb := '[]'; prev jsonb := '[]'; flagged int := 0; eid bigint; tot_d numeric := 0; tot_c numeric := 0; lim int := least(greatest(coalesce(p_limit, 1500), 1), 5000);
        trial jsonb; skipped jsonb := '[]'; acc jsonb := '[]';
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true, 'dry', p_dry); end if;
  if not p_dry and not public.rule_on('accounting_on') then raise exception 'accounting_off'; end if;
  if not p_dry then perform pg_advisory_xact_lock(hashtextextended('acct_post', 0)); end if;
  for d in select * from public._acct_docs(st) order by 3, 1, 2 loop
    if d.waiting is not null then waiting := jsonb_set(waiting, array[d.waiting], to_jsonb(coalesce((waiting->>d.waiting)::int, 0) + 1)); continue; end if;
    if n >= lim then more := true; exit; end if;
    begin
      if d.live then
        if public._acct_locked(d.entry_date) then locked := locked + 1; continue; end if;
        ln := public._acct_resolve(public._acct_merge(d.lines), d.location_id);
        if p_dry then
          acc := acc || (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', (x->>'debit')::numeric, 'credit', (x->>'credit')::numeric)), '[]'::jsonb)
                         from jsonb_array_elements(ln) x join public.coa_accounts a on a.id = (x->>'account_id')::bigint);
          if jsonb_array_length(prev) < 60 then
            prev := prev || jsonb_build_object('date', d.entry_date, 'source_type', d.source_type, 'source_id', d.source_id, 'memo', d.memo, 'flags', d.flags, 'location_id', d.location_id,
              'lines', (select jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', (x->>'debit')::numeric, 'credit', (x->>'credit')::numeric, 'party_type', x->>'party_type', 'party_id', x->>'party_id'))
                        from jsonb_array_elements(ln) x join public.coa_accounts a on a.id = (x->>'account_id')::bigint));
          end if;
        else
          eid := public._acct_write(d.entry_date, d.location_id, d.source_type, d.source_id, d.subtype, d.memo, d.flags, ln);
        end if;
        posted := posted + 1;
        if d.flags like '%cogs_missing%' then flagged := flagged + 1; end if;
        by_type := jsonb_set(by_type, array[d.source_type], to_jsonb(coalesce((by_type->>d.source_type)::int, 0) + 1));
      else
        select * into orig from public.journal_entries o where o.source_type = d.source_type and o.source_id = d.source_id and o.reverses_id is null;
        rdate := greatest(coalesce(d.void_date, public._acct_today()), orig.entry_date);
        if public._acct_locked(rdate) then locked := locked + 1; continue; end if;
        if p_dry then
          acc := acc || (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', l.credit, 'credit', l.debit)), '[]'::jsonb)
                         from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where l.entry_id = orig.id);
          if jsonb_array_length(prev) < 60 then
            prev := prev || jsonb_build_object('date', rdate, 'source_type', d.source_type, 'source_id', d.source_id, 'memo', 'Reversal: ' || orig.memo, 'reversal', true, 'location_id', orig.location_id,
              'lines', (select jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', l.credit, 'credit', l.debit, 'party_type', l.party_type, 'party_id', l.party_id) order by l.line_no)
                        from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where l.entry_id = orig.id));
          end if;
        else
          eid := public._acct_reverse(orig.id, rdate, 'Reversal: ' || orig.memo);
        end if;
        rev := rev + 1;
        by_type := jsonb_set(by_type, array[d.source_type || '_reversed'], to_jsonb(coalesce((by_type->>(d.source_type || '_reversed'))::int, 0) + 1));
      end if;
      n := n + 1;
    exception when others then
      errors := errors || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'error', sqlerrm);
      n := n + 1;
    end;
  end loop;
  if p_dry then
    select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name_bn', name_bn, 'name_en', name_en, 'debit', dr, 'credit', cr) order by code), '[]'::jsonb), coalesce(sum(dr), 0), coalesce(sum(cr), 0)
      into trial, tot_d, tot_c from (select x->>'code' code, x->>'name_bn' name_bn, x->>'name_en' name_en, sum((x->>'debit')::numeric) dr, sum((x->>'credit')::numeric) cr from jsonb_array_elements(acc) x group by 1, 2, 3) z;
  end if;
  if to_regclass('public.staff_advances') is null then skipped := skipped || to_jsonb('staff_advances'::text); end if;
  if to_regclass('public.salary_payments') is null then skipped := skipped || to_jsonb('salary_payments'::text); end if;
  res := jsonb_build_object('dry', p_dry, 'start', st, 'posted', posted, 'reversed', rev, 'by_type', by_type, 'locked', locked, 'waiting', waiting, 'cogs_missing', flagged,
    'errors', errors, 'more', more, 'skipped_sources', skipped);
  if p_dry then res := res || jsonb_build_object('preview', prev, 'trial', trial, 'total_debit', tot_d, 'total_credit', tot_c); end if;
  return res;
end $$;

-- ---------- manual journal, opening balances ----------
create or replace function public.acct_journal_post(p_date date, p_loc int, p_memo text, p_lines jsonb, p_client uuid default null, p_photo text default null, p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if st is null then raise exception 'data_needed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_memo is null or length(btrim(p_memo)) < 3 then raise exception 'memo_required'; end if;
  if p_date is null then raise exception 'bad_date'; end if;
  if p_date < st then raise exception 'before_start'; end if;
  if p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  perform public.lock_check(p_date);
  ln := public._acct_resolve(p_lines, p_loc);
  for x in select * from jsonb_array_elements(ln) loop td := td + (x->>'debit')::numeric; tc := tc + (x->>'credit')::numeric; end loop;
  if td <> tc or td <= 0 then raise exception 'unbalanced' using detail = 'debit ' || td::text || ' credit ' || tc::text; end if;
  if p_dry then return jsonb_build_object('dry', true, 'date', p_date, 'total_debit', td, 'total_credit', tc, 'lines', jsonb_array_length(ln)); end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then
      if r.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', r.id);
    end if;
  end if;
  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, null, ln, null, p_client, p_photo);
  return jsonb_build_object('id', id_, 'total', td);
end $$;

create or replace function public.acct_journal_reverse(p_id bigint, p_note text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.journal_entries; r public.journal_entries; id_ bigint; dt date;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  select * into o from public.journal_entries where id = p_id;
  if not found then raise exception 'not found'; end if;
  if o.source_type not in ('manual', 'opening') then raise exception 'use_source: reverse the business document instead'; end if;
  if o.location_id is not null and not public.can_loc(o.location_id) then raise exception 'not allowed for this location'; end if;
  dt := greatest(public._acct_today(), o.entry_date);
  perform public.lock_check(dt);
  id_ := public._acct_reverse(p_id, dt, 'Reversal (' || left(btrim(p_note), 150) || '): ' || o.memo, p_client);
  return jsonb_build_object('id', id_);
end $$;

create or replace function public.acct_opening(p_lines jsonb, p_plug boolean default false, p_memo text default null, p_client uuid default null, p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st date := public._acct_start(); ln jsonb; x jsonb; td numeric := 0; tc numeric := 0; diff numeric; plug bigint; r public.journal_entries; id_ bigint; ty text;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if st is null then raise exception 'data_needed'; end if;
  if exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null and not exists (select 1 from public.journal_entries r2 where r2.reverses_id = o.id)) then raise exception 'opening_exists'; end if;
  if exists (select 1 from public.journal_entries where entry_date < st and source_type <> 'opening') then raise exception 'postings_before_opening'; end if;
  ln := public._acct_resolve(p_lines, null);
  for x in select * from jsonb_array_elements(ln) loop
    select type into ty from public.coa_accounts where id = (x->>'account_id')::bigint;
    if ty in ('income', 'expense') then raise exception 'opening_balance_sheet_only'; end if;
    td := td + (x->>'debit')::numeric; tc := tc + (x->>'credit')::numeric;
  end loop;
  diff := round(td - tc, 2);
  if diff <> 0 then
    if not coalesce(p_plug, false) then raise exception 'unbalanced' using detail = 'debit ' || td::text || ' credit ' || tc::text; end if;
    select account_id into plug from public.acct_mappings where key = 'retained';
    if plug is null then raise exception 'mapping_missing:retained'; end if;
    ln := ln || jsonb_build_object('account_id', plug, 'debit', case when diff < 0 then -diff else 0 end, 'credit', case when diff > 0 then diff else 0 end, 'party_type', null, 'party_id', null, 'memo', 'balancing figure', 'location_id', null);
    if diff > 0 then tc := tc + diff; else td := td - diff; end if;
  end if;
  if td <= 0 then raise exception 'no_lines'; end if;
  if p_dry then return jsonb_build_object('dry', true, 'date', st, 'total_debit', td, 'total_credit', tc, 'plug', diff, 'lines', jsonb_array_length(ln)); end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  id_ := public._acct_write(st, null, 'opening', 'opening:' || coalesce(p_client::text, gen_random_uuid()::text), null, coalesce(nullif(btrim(p_memo), ''), 'Opening balances'), null, ln, null, p_client, null);
  return jsonb_build_object('id', id_, 'date', st, 'plug', diff);
end $$;

-- ---------- reports ----------
-- balances per account (visible places only): opening net (before p_from), debits and credits inside [p_from, p_to], rolled up through the groups
create or replace function public._acct_bal(p_from date, p_to date, p_loc int) returns table(account_id bigint, open_net numeric, dr numeric, cr numeric)
language plpgsql stable security definer set search_path = public as $$
declare v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); f date := coalesce(p_from, date '1900-01-01');
begin
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return query
  with recursive b as (
    select l.account_id aid,
      coalesce(sum(l.debit - l.credit) filter (where e.entry_date < f), 0) o,
      coalesce(sum(l.debit) filter (where e.entry_date >= f), 0) d, coalesce(sum(l.credit) filter (where e.entry_date >= f), 0) c
    from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    where e.entry_date <= coalesce(p_to, date '2999-12-31')
      and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
    group by l.account_id),
  anc(acc, anc_id) as (select a.id, a.id from public.coa_accounts a union all select n.acc, p.parent_id from anc n join public.coa_accounts p on p.id = n.anc_id where p.parent_id is not null)
  select anc.anc_id, sum(b.o), sum(b.d), sum(b.c) from anc join b on b.aid = anc.acc group by anc.anc_id;
end $$;

create or replace function public.acct_trial_balance(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); rows_ jsonb; td numeric; tc numeric; to_ date := coalesce(p_to, public._acct_today()); fr date;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  fr := coalesce(p_from, st);
  if fr > to_ then raise exception 'bad_range'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'type', a.type, 'parent_id', a.parent_id, 'is_group', a.is_group,
      'open_dr', greatest(b.open_net, 0), 'open_cr', greatest(-b.open_net, 0), 'dr', b.dr, 'cr', b.cr,
      'close_dr', greatest(b.open_net + b.dr - b.cr, 0), 'close_cr', greatest(-(b.open_net + b.dr - b.cr), 0)) order by a.code), '[]'::jsonb),
    coalesce(sum(greatest(b.open_net + b.dr - b.cr, 0)) filter (where not a.is_group), 0), coalesce(sum(greatest(-(b.open_net + b.dr - b.cr), 0)) filter (where not a.is_group), 0)
    into rows_, td, tc
    from public._acct_bal(fr, to_, p_loc) b join public.coa_accounts a on a.id = b.account_id
    where b.open_net <> 0 or b.dr <> 0 or b.cr <> 0;
  return jsonb_build_object('from', fr, 'to', to_, 'location_id', p_loc, 'rows', rows_, 'total_debit', td, 'total_credit', tc, 'balanced', td = tc, 'diff', td - tc);
end $$;

create or replace function public.acct_income_statement(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); inc jsonb; exp_ jsonb; ti numeric; te numeric; cg numeric := 0; cid bigint; to_ date := coalesce(p_to, public._acct_today()); fr date; cm bigint;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  fr := coalesce(p_from, st);
  if fr > to_ then raise exception 'bad_range'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'parent_id', a.parent_id, 'is_group', a.is_group, 'amount', (b.cr - b.dr)) order by a.code), '[]'::jsonb),
         coalesce(sum(b.cr - b.dr) filter (where not a.is_group), 0)
    into inc, ti from public._acct_bal(fr, to_, p_loc) b join public.coa_accounts a on a.id = b.account_id where a.type = 'income' and (b.dr <> 0 or b.cr <> 0);
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'parent_id', a.parent_id, 'is_group', a.is_group, 'amount', (b.dr - b.cr)) order by a.code), '[]'::jsonb),
         coalesce(sum(b.dr - b.cr) filter (where not a.is_group), 0)
    into exp_, te from public._acct_bal(fr, to_, p_loc) b join public.coa_accounts a on a.id = b.account_id where a.type = 'expense' and (b.dr <> 0 or b.cr <> 0);
  select account_id into cid from public.acct_mappings where key = 'cogs';
  select coalesce(sum(b.dr - b.cr), 0) into cg from public._acct_bal(fr, to_, p_loc) b where b.account_id = cid;
  select count(*) into cm from public.journal_entries e where e.entry_date between fr and to_ and e.flags like '%cogs_missing%' and e.reverses_id is null
    and (public._acct_all() or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc);
  return jsonb_build_object('from', fr, 'to', to_, 'location_id', p_loc, 'income', inc, 'expense', exp_, 'total_income', ti, 'total_expense', te, 'cogs', cg,
    'gross_profit', ti - cg, 'net_profit', ti - te, 'cogs_missing', cm);
end $$;

create or replace function public.acct_balance_sheet(p_as_of date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); as_ date := coalesce(p_as_of, public._acct_today()); ass jsonb; lia jsonb; eq jsonb; ta numeric; tl numeric; te numeric; earn numeric; diff numeric; cm bigint;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'parent_id', a.parent_id, 'is_group', a.is_group, 'amount', (b.open_net + b.dr - b.cr)) order by a.code), '[]'::jsonb),
         coalesce(sum(b.open_net + b.dr - b.cr) filter (where not a.is_group), 0)
    into ass, ta from public._acct_bal(null, as_, p_loc) b join public.coa_accounts a on a.id = b.account_id where a.type = 'asset' and (b.dr <> 0 or b.cr <> 0 or b.open_net <> 0);
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'parent_id', a.parent_id, 'is_group', a.is_group, 'amount', -(b.open_net + b.dr - b.cr)) order by a.code), '[]'::jsonb),
         coalesce(sum(-(b.open_net + b.dr - b.cr)) filter (where not a.is_group), 0)
    into lia, tl from public._acct_bal(null, as_, p_loc) b join public.coa_accounts a on a.id = b.account_id where a.type = 'liability' and (b.dr <> 0 or b.cr <> 0 or b.open_net <> 0);
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'parent_id', a.parent_id, 'is_group', a.is_group, 'amount', -(b.open_net + b.dr - b.cr)) order by a.code), '[]'::jsonb),
         coalesce(sum(-(b.open_net + b.dr - b.cr)) filter (where not a.is_group), 0)
    into eq, te from public._acct_bal(null, as_, p_loc) b join public.coa_accounts a on a.id = b.account_id where a.type = 'equity' and (b.dr <> 0 or b.cr <> 0 or b.open_net <> 0);
  select coalesce(sum(-(b.open_net + b.dr - b.cr)) filter (where a.type = 'income' and not a.is_group), 0) - coalesce(sum(b.open_net + b.dr - b.cr) filter (where a.type = 'expense' and not a.is_group), 0)
    into earn from public._acct_bal(null, as_, p_loc) b join public.coa_accounts a on a.id = b.account_id;
  diff := round(ta - (tl + te + earn), 2);
  select count(*) into cm from public.journal_entries e where e.entry_date <= as_ and e.flags like '%cogs_missing%' and e.reverses_id is null
    and (public._acct_all() or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc);
  return jsonb_build_object('as_of', as_, 'location_id', p_loc, 'assets', ass, 'liabilities', lia, 'equity', eq, 'total_assets', ta, 'total_liabilities', tl, 'total_equity', te,
    'retained_earnings', earn, 'total_equity_and_earnings', te + earn, 'total_liabilities_and_equity', tl + te + earn, 'unbalanced', diff <> 0, 'difference', diff, 'cogs_missing', cm);
end $$;

create or replace function public.acct_ledger(p_account bigint, p_from date, p_to date, p_loc int default null, p_limit int default 1000) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); a public.coa_accounts; v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); to_ date := coalesce(p_to, public._acct_today()); fr date; open_ numeric; rows_ jsonb;
        lim int := least(greatest(coalesce(p_limit, 1000), 1), 5000); sgn int; ids bigint[];
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select * into a from public.coa_accounts where id = p_account;
  if not found then raise exception 'unknown_account'; end if;
  fr := coalesce(p_from, st);
  sgn := case a.normal_side when 'debit' then 1 else -1 end;
  select array(with recursive t(id) as (select p_account union all select c.id from public.coa_accounts c join t on c.parent_id = t.id) select id from t) into ids;
  select coalesce(sum(l.debit - l.credit), 0) * sgn into open_ from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    where l.account_id = any (ids) and e.entry_date < fr and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc);
  select coalesce(jsonb_agg(jsonb_build_object('date', w.entry_date, 'entry_id', w.entry_id, 'line_no', w.line_no, 'memo', w.memo, 'line_memo', w.lmemo, 'source_type', w.source_type, 'source_id', w.source_id,
      'account_code', w.code, 'party_type', w.party_type, 'party_id', w.party_id, 'location_id', w.location_id, 'debit', w.debit, 'credit', w.credit, 'balance', w.bal, 'reversal', w.reverses_id is not null)
      order by w.entry_date, w.entry_id, w.line_no), '[]'::jsonb)
    into rows_ from (
      select z.*, open_ + sum((z.debit - z.credit) * sgn) over (order by z.entry_date, z.entry_id, z.line_no) bal from (
        select e.entry_date, e.id entry_id, l.line_no, e.memo, l.memo lmemo, e.source_type, e.source_id, e.reverses_id, ac.code, l.party_type, l.party_id, l.location_id, l.debit, l.credit
        from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts ac on ac.id = l.account_id
        where l.account_id = any (ids) and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
        order by e.entry_date, e.id, l.line_no limit lim) z) w;
  return jsonb_build_object('account', jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'type', a.type, 'normal_side', a.normal_side, 'is_group', a.is_group),
    'from', fr, 'to', to_, 'opening', open_, 'rows', rows_,
    'closing', case when jsonb_array_length(rows_) = 0 then open_ else (rows_ -> (jsonb_array_length(rows_) - 1) ->> 'balance')::numeric end, 'truncated', jsonb_array_length(rows_) >= lim);
end $$;

create or replace function public.acct_journal_book(p_from date, p_to date, p_loc int default null, p_limit int default 200, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); v_all boolean := public._acct_all(); rows_ jsonb; lim int := least(greatest(coalesce(p_limit, 200), 1), 1000); to_ date := coalesce(p_to, public._acct_today()); fr date; tot bigint;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  fr := coalesce(p_from, st);
  select count(*) into tot from public.journal_entries e where e.entry_date between fr and to_ and (v_all or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc);
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'date', e.entry_date, 'location_id', e.location_id, 'source_type', e.source_type, 'source_id', e.source_id, 'subtype', e.subtype, 'memo', e.memo,
      'status', e.status, 'reverses_id', e.reverses_id, 'flags', e.flags, 'photo', e.photo, 'created_at', e.created_at, 'created_staff', e.created_staff,
      'lines', (select jsonb_agg(jsonb_build_object('line_no', l.line_no, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', l.debit, 'credit', l.credit, 'party_type', l.party_type, 'party_id', l.party_id, 'memo', l.memo) order by l.line_no)
                from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where l.entry_id = e.id)) order by e.entry_date desc, e.id desc), '[]'::jsonb)
    into rows_ from (select * from public.journal_entries e where e.entry_date between fr and to_ and (v_all or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc)
      order by e.entry_date desc, e.id desc limit lim offset greatest(coalesce(p_offset, 0), 0)) e;
  return jsonb_build_object('from', fr, 'to', to_, 'total', tot, 'rows', rows_);
end $$;

-- simple cash flow: the cash-like accounts (cash, bank, mobile wallets) and what moved them
create or replace function public.acct_cash_flow(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); ids bigint[]; to_ date := coalesce(p_to, public._acct_today()); fr date; open_ numeric; rows_ jsonb; ti numeric; tout numeric;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  fr := coalesce(p_from, st);
  select array_agg(account_id) into ids from public.acct_mappings where key in ('pay_cash', 'pay_bank', 'pay_mobile');
  select coalesce(sum(l.debit - l.credit), 0) into open_ from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    where l.account_id = any (ids) and e.entry_date < fr and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc);
  select coalesce(jsonb_agg(jsonb_build_object('category', cat, 'in', i, 'out', o, 'net', i - o) order by cat), '[]'::jsonb), coalesce(sum(i), 0), coalesce(sum(o), 0) into rows_, ti, tout from (
    select coalesce(e.subtype, e.source_type) cat, sum(l.debit) i, sum(l.credit) o
    from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    where l.account_id = any (ids) and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
    group by 1) z;
  return jsonb_build_object('from', fr, 'to', to_, 'opening', open_, 'rows', rows_, 'total_in', ti, 'total_out', tout, 'closing', open_ + ti - tout);
end $$;

-- customer / supplier sub-ledger (the party tag on the lines)
create or replace function public.acct_party_ledger(p_type text, p_id text, p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); sgn int; open_ numeric; rows_ jsonb; to_ date := coalesce(p_to, public._acct_today()); fr date;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_type is null or p_type not in ('customer', 'supplier', 'staff', 'partner') or p_id is null then raise exception 'bad_party'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  fr := coalesce(p_from, st);
  sgn := case p_type when 'customer' then 1 when 'staff' then 1 else -1 end;      -- a customer owes us (debit); we owe a supplier (credit)
  select coalesce(sum(l.debit - l.credit), 0) * sgn into open_ from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    where l.party_type = p_type and l.party_id = p_id and e.entry_date < fr and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc);
  select coalesce(jsonb_agg(jsonb_build_object('date', w.entry_date, 'entry_id', w.entry_id, 'memo', w.memo, 'source_type', w.source_type, 'source_id', w.source_id, 'account_code', w.code,
      'debit', w.debit, 'credit', w.credit, 'balance', w.bal) order by w.entry_date, w.entry_id, w.line_no), '[]'::jsonb) into rows_ from (
    select z.*, open_ + sum((z.debit - z.credit) * sgn) over (order by z.entry_date, z.entry_id, z.line_no) bal from (
      select e.entry_date, e.id entry_id, l.line_no, e.memo, e.source_type, e.source_id, a.code, l.debit, l.credit
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
      where l.party_type = p_type and l.party_id = p_id and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
      order by e.entry_date, e.id, l.line_no limit 2000) z) w;
  return jsonb_build_object('party_type', p_type, 'party_id', p_id, 'from', fr, 'to', to_, 'opening', open_, 'rows', rows_,
    'closing', case when jsonb_array_length(rows_) = 0 then open_ else (rows_ -> (jsonb_array_length(rows_) - 1) ->> 'balance')::numeric end);
end $$;

-- the sub-ledgers against the existing customer / supplier balances (differences only)
create or replace function public.acct_reconcile(p_kind text default 'all') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); cust jsonb := '[]'; sup jsonb := '[]'; unattr numeric := 0; nc int := 0; ns int := 0; ar bigint; ap bigint; adv bigint;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if not public._acct_all() then raise exception 'not allowed'; end if;           -- a reconciliation covers every place: owner / management only
  if st is null then return jsonb_build_object('data_needed', true); end if;
  select account_id into ar from public.acct_mappings where key = 'receivable';
  select account_id into ap from public.acct_mappings where key = 'payable';
  select account_id into adv from public.acct_mappings where key = 'cust_advance';
  if p_kind in ('all', 'customer') then
    select coalesce(jsonb_agg(jsonb_build_object('party_id', x.pid, 'name', x.nm, 'journal', x.j, 'existing', x.l, 'advance_applied', x.av, 'difference', x.j - x.l, 'unexplained', x.j - x.l + x.av) order by abs(x.j - x.l + x.av) desc), '[]'::jsonb), count(*)
      into cust, nc from (
      select c.id::text pid, c.name nm, coalesce(j.bal, 0) j, coalesce(public._cust_bal(c.id), 0) l,
             coalesce((select sum(m.amount) from public.cash_moves m where m.customer_id = c.id and m.kind = 'cust_advance_used' and m.status = 'done' and m.move_date >= st), 0) av
      from public.customers c left join (select party_id, sum(debit - credit) bal from public.journal_lines where account_id = ar and party_type = 'customer' group by party_id) j on j.party_id = c.id::text
      where coalesce(j.bal, 0) <> 0 or coalesce(public._cust_bal(c.id), 0) <> 0) x
      where abs(x.j - x.l + x.av) > 0.005;
    select coalesce(sum(debit - credit), 0) into unattr from public.journal_lines where account_id = ar and party_id is null;
  end if;
  if p_kind in ('all', 'supplier') then
    select coalesce(jsonb_agg(jsonb_build_object('party_id', x.pid, 'name', x.nm, 'journal', x.j, 'existing', x.l, 'difference', x.j - x.l, 'unexplained', x.j - x.l) order by abs(x.j - x.l) desc), '[]'::jsonb), count(*)
      into sup, ns from (
      select s.id::text pid, s.name nm, coalesce(j.bal, 0) j, coalesce(public._sup_balance(s.id), 0) l
      from public.suppliers s left join (select party_id, sum(credit - debit) bal from public.journal_lines where account_id = ap and party_type = 'supplier' group by party_id) j on j.party_id = s.id::text
      where coalesce(j.bal, 0) <> 0 or coalesce(public._sup_balance(s.id), 0) <> 0) x
      where abs(x.j - x.l) > 0.005;
  end if;
  return jsonb_build_object('start', st, 'customers', cust, 'customers_off', nc, 'suppliers', sup, 'suppliers_off', ns, 'unattributed_receivable', unattr,
    'note', 'A difference equal to a balance that existed before the start date means that party has no opening balance in the books yet.');
end $$;

-- one call for the overview page
create or replace function public.acct_overview(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); t date := public._acct_today(); bs jsonb; isx jsonb; pend jsonb;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true, 'on', public.rule_on('accounting_on')); end if;
  bs := public.acct_balance_sheet(t, p_loc);
  isx := public.acct_income_statement(greatest(date_trunc('month', t)::date, st), t, p_loc);
  return jsonb_build_object('start', st, 'on', public.rule_on('accounting_on'), 'balance_sheet', jsonb_build_object('total_assets', bs->'total_assets', 'total_liabilities', bs->'total_liabilities',
      'total_equity', bs->'total_equity_and_earnings', 'unbalanced', bs->'unbalanced', 'difference', bs->'difference', 'cogs_missing', bs->'cogs_missing'),
    'income_month', jsonb_build_object('total_income', isx->'total_income', 'total_expense', isx->'total_expense', 'net_profit', isx->'net_profit', 'cogs', isx->'cogs', 'gross_profit', isx->'gross_profit', 'from', isx->'from'),
    'status', public.acct_status());
end $$;

-- ---------- grants ----------
revoke all on function public._acct_ro(), public._acct_balance_chk(), public._acct_coa_guard() from public, anon, authenticated;
revoke all on function public._acct_view(), public._acct_manage(), public._acct_all(), public._acct_locs(), public._acct_start(), public._acct_today(), public._acct_locked(date) from public, anon, authenticated;
revoke all on function public._acct_num(text), public._acct_inv_key(text), public._acct_buy_key(text), public._acct_paykey(text, boolean), public._acct_need(text, text, boolean), public._acct_purchase_alloc(uuid) from public, anon, authenticated;
revoke all on function public._acct_docs(date), public._acct_resolve(jsonb, int), public._acct_merge(jsonb), public._acct_bal(date, date, int) from public, anon, authenticated;
revoke all on function public._acct_write(date, int, text, text, text, text, text, jsonb, bigint, uuid, text), public._acct_reverse(bigint, date, text, uuid) from public, anon, authenticated;
revoke all on function public.acct_status(), public.acct_set_start(date), public.acct_account_save(bigint, text, text, text, text, bigint, boolean, int, boolean), public.acct_mapping_set(text, bigint),
  public.acct_post_pending(boolean, int), public.acct_journal_post(date, int, text, jsonb, uuid, text, boolean), public.acct_journal_reverse(bigint, text, uuid),
  public.acct_opening(jsonb, boolean, text, uuid, boolean), public.acct_trial_balance(date, date, int), public.acct_income_statement(date, date, int), public.acct_balance_sheet(date, int),
  public.acct_ledger(bigint, date, date, int, int), public.acct_journal_book(date, date, int, int, int), public.acct_cash_flow(date, date, int),
  public.acct_party_ledger(text, text, date, date, int), public.acct_reconcile(text), public.acct_overview(int) from public, anon;
grant execute on function public.acct_status(), public.acct_set_start(date), public.acct_account_save(bigint, text, text, text, text, bigint, boolean, int, boolean), public.acct_mapping_set(text, bigint),
  public.acct_post_pending(boolean, int), public.acct_journal_post(date, int, text, jsonb, uuid, text, boolean), public.acct_journal_reverse(bigint, text, uuid),
  public.acct_opening(jsonb, boolean, text, uuid, boolean), public.acct_trial_balance(date, date, int), public.acct_income_statement(date, date, int), public.acct_balance_sheet(date, int),
  public.acct_ledger(bigint, date, date, int, int), public.acct_journal_book(date, date, int, int, int), public.acct_cash_flow(date, date, int),
  public.acct_party_ledger(text, text, date, date, int), public.acct_reconcile(text), public.acct_overview(int) to authenticated;

-- the read policies call this one as the caller (it only answers yes / no about the caller)
grant execute on function public._acct_view(), public._acct_all() to authenticated;
