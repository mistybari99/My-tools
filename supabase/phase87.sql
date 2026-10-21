-- Phase 87 (bos87) - MONEY ACCOUNTS. Paste LAST (after phase86), paste-twice safe. Earlier phase files are not edited.
-- Owner decision (final): the money source of any payment is NOT fixed. Cash drawer, mobile wallet (any provider) or bank account, chosen per payment.
--
-- WHAT EXISTED (inventory, reused and not duplicated)
--   chart of accounts + double-entry journal (phase40), mapping keys, _acct_docs scanner, acct_post_pending (autopost), manual journal, reversal
--   opening_balance_post (phase80)           -> reused: gets one more section "money"; no second opening path
--   d_wallets / d_wallet_* (phase83)         -> left as it is (legacy register of bKash, Nagad, Rocket, Upay on accounts 1131-1134). Its switch d_wallet_split_on only
--                                               governs that legacy text based split of 1130. Money accounts of kind wallet NEVER depend on it (see below).
--   _d_cash_ok (10-3 / accounts permission)  -> reused for the real-balance check; the blind count rule (real figure typed first) is the same as d_wallet_checks
--   quick expense / cash_moves / payroll / partner tables -> reused: each only gets one nullable column money_account_id
--   Balance Check (phase84), day book (phase13/23/50), cash flow (phase40), daybook_vs_journal (phase49/52) -> patched in place (text patch of the live function), nothing duplicated
--   salary_pay_source (phase82, a FIXED source for salary) -> kept as the fallback for a payment that names no money account
-- WHAT THIS FILE ADDS
--   money_accounts (registry: cash drawer per place, wallet per provider and number, bank per bank/branch/account number), each on its own chart account
--   money_event_settings (per event type: default source, allow override, require source)
--   a payment source on 14 event types, carried IN BAND on the record (so an offline saved payment keeps it): the text "ma#<id>;" in front of the free text field
--     of the payment (wallet / ref / note column, see _m_tagcol), or the key money_account_id inside the 10-2 form data. A BEFORE INSERT trigger reads it, checks it,
--     sets money_account_id and the payment mode, removes the tag. The journal line then hits exactly that account (mapping key m_acct_<id>).
--   transfers between accounts (one balanced entry, optional fee), charges / interest, recurring transfers
--   per account statement, period summary, negative balance policy (warn | block | allow), real balance check, exceptions list, one-off owner exceptions
--   Balance Check item "money accounts total = mapped ledger accounts", day book shows the account, P&L / balance sheet per account
--   approver choice (any role, any named user, per entry) on top of phase80/86
-- NOTHING CHANGES FOR AN EXISTING INSTALL until the owner adds a money account and sets a default or the picker sends one: no rows are seeded, every setting
-- defaults to "no default, override allowed, source not required". !! Re-pasting phase 13, 40, 49, 50, 52, 79, 80, 82, 84, 85 or 86 removes the patches: paste this file again.

do $g$ begin
  if to_regprocedure('public._p86_present()') is null then raise exception 'phase87 needs phase86 (and 80-85) first'; end if;
  if to_regprocedure('public._acct_docs(date)') is null or to_regprocedure('public._c_docs(date)') is null or to_regprocedure('public.opening_balance_post(jsonb,uuid,boolean,boolean)') is null
     or to_regprocedure('public._e_balance_check(date,integer,integer)') is null or to_regprocedure('public._daybook_lines(integer[],integer[],date,date)') is null then
    raise exception 'phase87 needs the shared functions of phases 40, 80, 82, 84, 85';
  end if;
end $g$;

create or replace function public._p87_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic: patch a live function by exact text (reads the CURRENT definition, so it sits on top of whatever is installed) ----------
-- p_pairs = [old1, new1, old2, new2 ...]. Every old text must exist (otherwise the paste stops, nothing is half changed). Already patched (marker bos87) = no-op.
create or replace function public._m_patch(p_fn regprocedure, p_pairs text[]) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  if position('bos87' in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception 'phase87 patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position('bos87' in def) = 0 then raise exception 'phase87 patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;

-- ---------- tables ----------
create sequence if not exists public.money_account_code_seq;
create table if not exists public.money_accounts (
  id bigserial primary key,
  code text not null unique,
  kind text not null check (kind in ('cash', 'wallet', 'bank')),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 120),
  name_en text not null check (length(btrim(name_en)) between 1 and 120),
  provider text check (provider is null or length(provider) <= 80),          -- wallet company or bank name
  branch text check (branch is null or length(branch) <= 80),
  account_no text check (account_no is null or length(account_no) <= 40),    -- wallet number or bank account number
  location_id int references public.locations(id),                          -- cash drawer: the place
  coa_account_id bigint not null unique references public.coa_accounts(id),
  neg_policy text not null default 'warn' check (neg_policy in ('warn', 'block', 'allow')),
  active boolean not null default true,
  sort int not null default 100,
  opening_amount numeric not null default 0 check (opening_amount >= 0 and opening_amount <= 1000000000000),
  opening_date date,
  opening_posted boolean not null default false,
  note text check (note is null or length(note) <= 300),
  deactivated_by uuid, deactivated_at timestamptz, deactivate_reason text,
  created_at timestamptz not null default now(), created_by uuid
);
create unique index if not exists money_accounts_ident on public.money_accounts (kind, lower(coalesce(provider, '')), lower(coalesce(account_no, '')), coalesce(location_id, 0), (case when kind = 'cash' then lower(name_en) else '' end)) where active;

create table if not exists public.money_event_settings (
  event_type text primary key,
  label_en text not null, dir text not null check (dir in ('out', 'in', 'both')),
  default_account_id bigint references public.money_accounts(id),
  allow_override boolean not null default true,
  require_source boolean not null default false,
  sort int not null default 100,
  updated_by uuid, updated_at timestamptz not null default now()
);
insert into public.money_event_settings (event_type, label_en, dir, sort) values
  ('salary_payment', 'Salary payment', 'out', 10), ('salary_advance', 'Salary advance (recovery rides on the salary payment)', 'out', 20),
  ('expense_10_2', 'Expense voucher 10-2', 'out', 30), ('quick_expense', 'Quick expense', 'out', 40),
  ('supplier_payment', 'Supplier payment', 'out', 50), ('purchase_payment', 'Purchase payment (paid with the bill)', 'out', 60),
  ('owner_topup', 'Owner top-up', 'in', 70), ('owner_draw', 'Owner draw', 'out', 80),
  ('partner_capital', 'Partner capital / loan (in and out)', 'both', 90), ('partner_payout', 'Partner profit payout', 'out', 100),
  ('customer_refund', 'Customer refund', 'out', 110), ('supplier_refund', 'Supplier refund received', 'in', 120),
  ('customer_advance', 'Customer advance (taken and refunded)', 'both', 130), ('cash_handover', 'Cash handover received (hub)', 'in', 140)
on conflict (event_type) do nothing;

alter table public.supplier_payments add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.supplier_refunds add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.sale_returns add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.quick_expenses add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.cash_moves add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.payroll_payments add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.employee_advances add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.partner_capital add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.partner_settlement_payments add column if not exists money_account_id bigint references public.money_accounts(id);

create table if not exists public.money_transfers (
  id bigserial primary key,
  client_id uuid unique,
  from_account bigint not null references public.money_accounts(id),
  to_account bigint not null references public.money_accounts(id),
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  fee numeric not null default 0 check (fee >= 0 and fee <= 1000000000),
  fee_side text not null default 'from' check (fee_side in ('from', 'to')),
  xfer_date date not null,
  location_id int references public.locations(id),
  ref text check (ref is null or length(ref) <= 60),
  note text check (note is null or length(note) <= 200),
  status text not null default 'done' check (status in ('done', 'void')),
  void_note text, void_by uuid, void_at timestamptz,
  recurring_id bigint,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  check (from_account <> to_account)
);
create index if not exists money_transfers_d on public.money_transfers (xfer_date);

create table if not exists public.money_charges (
  id bigserial primary key,
  client_id uuid unique,
  account_id bigint not null references public.money_accounts(id),
  kind text not null check (kind in ('charge', 'interest')),
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  charge_date date not null,
  location_id int references public.locations(id),
  ref text check (ref is null or length(ref) <= 60),
  note text check (note is null or length(note) <= 200),
  status text not null default 'done' check (status in ('done', 'void')),
  void_note text, void_by uuid, void_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);

create table if not exists public.money_recurring (
  id bigserial primary key,
  name text not null check (length(btrim(name)) between 1 and 80),
  from_account bigint not null references public.money_accounts(id),
  to_account bigint not null references public.money_accounts(id),
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  fee numeric not null default 0 check (fee >= 0),
  fee_side text not null default 'from' check (fee_side in ('from', 'to')),
  day_of_month int not null check (day_of_month between 1 and 28),
  location_id int references public.locations(id),
  start_date date not null, end_date date,
  active boolean not null default true,
  last_run date,
  created_by uuid, created_at timestamptz not null default now(),
  check (from_account <> to_account)
);

alter table public.money_recurring add column if not exists location_id int references public.locations(id);

create table if not exists public.money_checks (               -- the real balance, typed FIRST (blind); same idea as d_wallet_checks (phase83) for every money account
  id bigserial primary key,
  account_id bigint not null references public.money_accounts(id),
  check_date date not null,
  real_balance numeric not null check (real_balance >= 0 and real_balance <= 1000000000000),
  book_balance numeric not null,
  diff numeric not null,                                       -- real - book, always written, even 0
  status text not null check (status in ('matched', 'difference', 'explained')),
  reason text check (reason is null or length(reason) <= 300), reason_by uuid, reason_at timestamptz,
  client_id uuid unique,
  counted_by uuid, counted_staff text, counted_at timestamptz not null default now()
);

create table if not exists public.money_exception_grants (     -- an owner allows ONE exception for ONE payment (reason required)
  id bigserial primary key,
  rule text not null check (rule in ('negative', 'require_source', 'override', 'period_lock', 'approver')),
  event_type text, for_user uuid, client_id uuid, account_id bigint references public.money_accounts(id),
  max_amount numeric, on_date date,
  reason text not null check (length(btrim(reason)) >= 3),
  granted_by uuid not null, granted_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '1 day'),
  used_at timestamptz, used_ref text, revoked boolean not null default false
);

create table if not exists public.money_exceptions (           -- the Exceptions list (append only, resolved by a note)
  id bigserial primary key,
  at timestamptz not null default now(),
  kind text not null check (kind in ('negative_warn', 'negative_block_exception', 'source_required_exception', 'override_exception', 'period_lock_exception', 'approver_exception', 'recon_diff')),
  event_type text, account_id bigint references public.money_accounts(id), amount numeric,
  src_table text, src_id text, reason text, by_user uuid,
  status text not null default 'open' check (status in ('open', 'resolved')),
  resolved_by uuid, resolved_at timestamptz, resolve_note text
);

do $t$ declare t text; begin
  foreach t in array array['money_accounts', 'money_event_settings', 'money_transfers', 'money_charges', 'money_recurring', 'money_checks', 'money_exception_grants', 'money_exceptions'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
  foreach t in array array['money_accounts', 'money_transfers', 'money_charges', 'money_recurring', 'money_checks', 'money_exception_grants', 'money_exceptions'] loop
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, 'id');
  end loop;
  drop trigger if exists audit_money_event_settings on public.money_event_settings;
  create trigger audit_money_event_settings after insert or update on public.money_event_settings for each row execute function public.log_change('event_type');
end $t$;

-- ---------- permission helpers ----------
create or replace function public._m_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._acct_manage()) $$;
create or replace function public._m_view() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._acct_view()) $$;

do $p$ declare t text; begin
  foreach t in array array['money_accounts', 'money_transfers', 'money_charges', 'money_recurring', 'money_checks', 'money_exceptions', 'money_event_settings'] loop
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._m_view())', t || '_read', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
  drop policy if exists money_exception_grants_read on public.money_exception_grants;
  create policy money_exception_grants_read on public.money_exception_grants for select to authenticated using (public.is_owner());
  grant select on public.money_exception_grants to authenticated;
end $p$;
grant execute on function public._m_mgr(), public._m_view() to authenticated;

-- ---------- small helpers ----------
create or replace function public._m_id(t text) returns bigint language sql immutable as $$ select case when t ~ '^[0-9]{1,12}$' then t::bigint end $$;
create or replace function public._m_key(p_id bigint, p_default text) returns text language sql immutable as $$ select case when p_id is null then p_default else 'm_acct_' || p_id::text end $$;
create or replace function public._m_mode_of_kind(p_kind text) returns text language sql immutable as $$ select case p_kind when 'cash' then 'cash' when 'wallet' then 'mobile' else 'bank' end $$;
create or replace function public._m_mode(t text) returns text language sql stable security definer set search_path = public as $$
  select public._m_mode_of_kind(a.kind) from public.money_accounts a where a.id = public._m_id(t) $$;
create or replace function public._m_name(p_id bigint) returns text language sql stable security definer set search_path = public as $$
  select a.name_en from public.money_accounts a where a.id = p_id $$;
create or replace function public._m_untag(p_text text, out acc bigint, out rest text) language sql immutable as $$
  select case when p_text ~ '^ma#[0-9]{1,12};' then substring(p_text from '^ma#([0-9]{1,12});')::bigint end,
         case when p_text ~ '^ma#[0-9]{1,12};' then nullif(regexp_replace(p_text, '^ma#[0-9]{1,12};', ''), '') else p_text end $$;
create or replace function public._m_linked_types() returns text[] language sql immutable as $$
  select array['supplier_payment', 'supplier_refund', 'sale_return', 'quick_expense', 'cash_move', 'payroll_payment', 'payroll_pay_accr', 'staff_advance', 'partner_capital',
               'partner_settle_pay', 'expense_voucher', 'money_transfer', 'money_charge'] $$;
-- sum of a 10-2 voucher exactly as the scanner reads it
create or replace function public._m_voucher_total(p_data jsonb) returns numeric language sql immutable set search_path = public as $$
  select coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0)
    from jsonb_array_elements(case when jsonb_typeof(p_data->'lines') = 'array' then p_data->'lines' else '[]'::jsonb end) x $$;

create or replace function public._m_journal_bal(p_acc bigint, p_asof date default null) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    join public.money_accounts a on a.coa_account_id = l.account_id where a.id = p_acc and (p_asof is null or e.entry_date <= p_asof) $$;
create or replace function public._m_is_generic(p_acc bigint) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.money_accounts a join public.acct_mappings m on m.account_id = a.coa_account_id and m.key in ('pay_cash', 'pay_bank', 'pay_mobile') where a.id = p_acc) $$;
create or replace function public._m_accounting_ready() returns boolean language sql stable security definer set search_path = public as $$
  select public.rule_on('accounting_on') and public._acct_start() is not null $$;

-- ---------- coa: bank charges and interest accounts (mapping keys used by charges and transfer fees) ----------
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'm_bank_charge', a.id, 'ব্যাংক চার্জ', 'Bank charges' from public.coa_accounts a where a.code = '5810' on conflict (key) do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'm_interest_income', a.id, 'সুদ / অন্যান্য আয়', 'Interest income' from public.coa_accounts a where a.code = '4900' on conflict (key) do nothing;

-- ============================================================================
-- PART B: the register of payments per account (_m_src), balance, exceptions, the payment source trigger
-- ============================================================================
-- every payment that names a money account, signed (+ into the account), with the journal source it will be posted under
create or replace function public._m_src(p_acc bigint default null)
returns table(tbl text, pk text, ev text, acc bigint, d date, loc int, amt numeric, jtype text, jid text, live boolean, memo text)
language sql stable security definer set search_path = public as $$
  select z.* from (
    select 'supplier_payments'::text as tbl, p.id::text as pk, (case when p.bill_id is not null then 'purchase_payment' else 'supplier_payment' end)::text as ev, p.money_account_id as acc,
           (p.paid_at at time zone 'Asia/Dhaka')::date as d, p.location_id as loc, -p.amount as amt, 'supplier_payment'::text as jtype, p.id::text as jid, not p.voided as live, 'Supplier payment'::text as memo
      from public.supplier_payments p where p.money_account_id is not null
    union all
    select 'supplier_refunds', f.id::text, 'supplier_refund', f.money_account_id, (f.refunded_at at time zone 'Asia/Dhaka')::date, f.location_id, f.amount, 'supplier_refund', f.id::text, not f.voided, 'Supplier refund'
      from public.supplier_refunds f where f.money_account_id is not null
    union all
    select 'sale_returns', r.id::text, 'customer_refund', r.money_account_id, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, -r.refund_amount, 'sale_return', r.id::text, r.status = 'done', 'Customer refund'
      from public.sale_returns r where r.money_account_id is not null and r.refund_amount > 0
    union all
    select 'quick_expenses', q.id::text, 'quick_expense', q.money_account_id, q.exp_date, q.location_id, -q.amount, 'quick_expense', q.id::text, q.status = 'done', 'Quick expense: ' || q.head
      from public.quick_expenses q where q.money_account_id is not null
    union all
    select 'cash_moves', m.id::text,
           case m.kind when 'owner_topup' then 'owner_topup' when 'owner_draw' then 'owner_draw' when 'hub_receipt' then 'cash_handover' else 'customer_advance' end,
           m.money_account_id, m.move_date, m.location_id,
           case m.kind when 'owner_draw' then -m.amount when 'cust_advance_refund' then -m.amount else m.amount end,
           'cash_move', public._acct_sid52('cash_move', m.id::text), m.status = 'done' and not public._shadowed52('cash_moves', m.id::text), 'Cash move: ' || m.kind
      from public.cash_moves m where m.money_account_id is not null and m.kind in ('owner_topup', 'owner_draw', 'cust_advance', 'cust_advance_refund', 'hub_receipt')
    union all
    select 'payroll_payments', p.id::text, 'salary_payment', p.money_account_id, p.pay_date, p.location_id, -p.amount,
           case when public._c_run_basis(p.run_id) = 'accrual' then 'payroll_pay_accr' else 'payroll_payment' end,
           case when public._c_run_basis(p.run_id) = 'accrual' then p.id::text else public._acct_sid52('payroll_payment', p.id::text) end,
           p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text), 'Salary payment PR-' || p.run_id::text
      from public.payroll_payments p where p.money_account_id is not null
    union all
    select 'employee_advances', a.id::text, 'salary_advance', a.money_account_id, a.adv_date, a.location_id, -a.amount, 'staff_advance', a.id::text,
           a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'), 'Staff advance ADV-' || a.id::text
      from public.employee_advances a where a.money_account_id is not null
    union all
    select 'partner_capital', c.id::text, 'partner_capital', c.money_account_id, c.cap_date, null::int,
           case when c.kind in ('contribution', 'loan_in') then c.amount else -c.amount end, 'partner_capital', public._acct_sid52('partner_capital', c.id::text),
           c.status = 'posted' and c.mode <> 'in_kind' and not public._shadowed52('partner_capital', c.id::text), 'Partner capital: ' || c.kind
      from public.partner_capital c where c.money_account_id is not null
    union all
    select 'partner_settlement_payments', pp.id::text, 'partner_payout', pp.money_account_id, pp.paid_on, null::int, -pp.amount, 'partner_settle_pay', pp.id::text,
           coalesce((select s.status <> 'void' from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id where l.id = pp.line_id), false), 'Partner payout'
      from public.partner_settlement_payments pp where pp.money_account_id is not null
    union all
    select 'entries', e.id::text, 'expense_10_2', public._m_id(e.data ->> 'money_account_id'), e.entry_date, e.location_id, -public._m_voucher_total(e.data), 'expense_voucher',
           e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.status = 'approved' and not public.is_shadow('entries', e.id::text), 'Expense voucher ' || e.serial::text
      from public.entries e where e.form_code = '10-2' and public._m_id(e.data ->> 'money_account_id') is not null
    union all
    select 'money_transfers', t.id::text, 'money_transfer', t.from_account, t.xfer_date, t.location_id, -(t.amount + case when t.fee_side = 'from' then t.fee else 0 end), 'money_transfer', t.id::text,
           t.status = 'done', 'Transfer out'
      from public.money_transfers t
    union all
    select 'money_transfers', t.id::text, 'money_transfer', t.to_account, t.xfer_date, t.location_id, t.amount - case when t.fee_side = 'to' then t.fee else 0 end, 'money_transfer', t.id::text,
           t.status = 'done', 'Transfer in'
      from public.money_transfers t
    union all
    select 'money_charges', c.id::text, 'money_charge', c.account_id, c.charge_date, c.location_id, case c.kind when 'interest' then c.amount else -c.amount end, 'money_charge', c.id::text,
           c.status = 'done', case c.kind when 'interest' then 'Interest' else 'Bank / wallet charge' end
      from public.money_charges c
  ) z
  where (p_acc is null or z.acc = p_acc) and (public._acct_start() is null or z.d >= public._acct_start()) $$;

-- book balance right now: the journal part that does not come from payments, plus every live payment on the account (posted or not yet)
create or replace function public._m_reg(p_acc bigint) returns numeric language plpgsql stable security definer set search_path = public as $$
declare a public.money_accounts; j numeric;
begin
  select * into a from public.money_accounts where id = p_acc;
  if not found then return null; end if;
  if public._m_is_generic(p_acc) then return public._m_journal_bal(p_acc); end if;
  select coalesce(sum(l.debit - l.credit), 0) into j from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
   where l.account_id = a.coa_account_id and e.source_type <> all (public._m_linked_types());
  return j + coalesce((select sum(s.amt) from public._m_src(p_acc) s where s.live), 0);
end $$;

-- the proof for one account: ledger = (non payment lines) + (posted live payments) + (voided payments whose reversal is still to come). Differences that are only "not posted yet" are timing.
create or replace function public._m_prove(p_acc bigint) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a public.money_accounts; jt numeric; jn numeric; lp numeric := 0; stl numeric := 0; pend numeric := 0; pn int := 0; r record;
begin
  select * into a from public.money_accounts where id = p_acc;
  if not found then return null; end if;
  jt := public._m_journal_bal(p_acc);
  if public._m_is_generic(p_acc) then return jsonb_build_object('account_id', p_acc, 'journal', jt, 'register', jt, 'diff', 0, 'pending', 0, 'pending_n', 0, 'stale', 0, 'generic', true); end if;
  select coalesce(sum(l.debit - l.credit), 0) into jn from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
   where l.account_id = a.coa_account_id and e.source_type <> all (public._m_linked_types());
  for r in select s.*, exists (select 1 from public.journal_entries e where e.source_type = s.jtype and e.source_id = s.jid and e.reverses_id is null) as posted,
                  exists (select 1 from public.journal_entries e join public.journal_entries x on x.reverses_id = e.id where e.source_type = s.jtype and e.source_id = s.jid and e.reverses_id is null) as reversed
             from public._m_src(p_acc) s loop
    if r.live and r.posted then lp := lp + r.amt;
    elsif r.live and not r.posted then pend := pend + r.amt; pn := pn + 1;
    elsif not r.live and r.posted and not r.reversed then stl := stl + r.amt; end if;
  end loop;
  return jsonb_build_object('account_id', p_acc, 'journal', jt, 'register', jn + lp + pend, 'diff', round(jt - (jn + lp + stl), 2), 'pending', pend, 'pending_n', pn, 'stale', stl, 'generic', false);
end $$;

-- ---------- exceptions: one-off, owner granted, reason required ----------
create or replace function public._m_grant_take(p_rule text, p_ev text, p_client uuid, p_acc bigint, p_amt numeric, p_date date, p_ref text) returns boolean
language plpgsql security definer set search_path = public as $$
declare g public.money_exception_grants; k text;
begin
  select * into g from public.money_exception_grants x
   where x.rule = p_rule and not x.revoked and x.used_at is null and x.expires_at > now()
     and (x.event_type is null or x.event_type = p_ev) and (x.account_id is null or x.account_id = p_acc) and (x.max_amount is null or p_amt is null or p_amt <= x.max_amount)
     and (x.on_date is null or x.on_date = p_date)
     and ((x.client_id is not null and x.client_id = p_client) or (x.client_id is null and x.for_user = auth.uid()))
   order by (x.client_id is not null) desc, x.id limit 1 for update skip locked;
  if not found then return false; end if;
  update public.money_exception_grants set used_at = now(), used_ref = left(coalesce(p_ref, ''), 80) where id = g.id;
  k := case p_rule when 'negative' then 'negative_block_exception' when 'require_source' then 'source_required_exception' when 'override' then 'override_exception'
         when 'period_lock' then 'period_lock_exception' else 'approver_exception' end;
  insert into public.money_exceptions (kind, event_type, account_id, amount, src_table, src_id, reason, by_user)
    values (k, p_ev, p_acc, p_amt, null, p_ref, g.reason || ' (granted by ' || coalesce((select staff_id from public.profiles where id = g.granted_by), '-') || ')', auth.uid());
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'money_exception_used', 'money_exception_grants', g.id::text,
      jsonb_build_object('rule', p_rule, 'event', p_ev, 'account', p_acc, 'amount', p_amt, 'ref', p_ref, 'reason', g.reason, 'granted_by', g.granted_by));
  return true;
end $$;

create or replace function public._m_neg_check(p_acc bigint, p_amt numeric, p_ev text, p_client uuid, p_date date, p_ref text) returns void
language plpgsql security definer set search_path = public as $$
declare a public.money_accounts; bal numeric;
begin
  select * into a from public.money_accounts where id = p_acc for update;         -- one outgoing payment at a time per account
  if not found or a.neg_policy = 'allow' or not public._m_accounting_ready() then return; end if;
  bal := public._m_reg(p_acc);
  if bal - p_amt >= 0 then return; end if;
  if a.neg_policy = 'block' then
    if public._m_grant_take('negative', p_ev, p_client, p_acc, p_amt, p_date, p_ref) then return; end if;
    raise exception 'money_negative' using detail = 'account ' || a.code || ' balance ' || bal::text || ' payment ' || p_amt::text;
  end if;
  insert into public.money_exceptions (kind, event_type, account_id, amount, src_id, reason, by_user)
    values ('negative_warn', p_ev, p_acc, p_amt, p_ref, 'balance ' || bal::text || ' before, ' || (bal - p_amt)::text || ' after', auth.uid());
end $$;

-- ---------- row readers for the source trigger ----------
create or replace function public._m_event(p_tbl text, r jsonb) returns text language sql immutable as $$
  select case p_tbl
    when 'supplier_payments' then case when r ->> 'bill_id' is not null then 'purchase_payment' else 'supplier_payment' end
    when 'supplier_refunds' then 'supplier_refund'
    when 'sale_returns' then case when coalesce((r ->> 'refund_amount')::numeric, 0) > 0 and r ->> 'refund_mode' is not null then 'customer_refund' end
    when 'quick_expenses' then 'quick_expense'
    when 'cash_moves' then case r ->> 'kind' when 'owner_topup' then 'owner_topup' when 'owner_draw' then 'owner_draw' when 'cust_advance' then 'customer_advance'
                                  when 'cust_advance_refund' then 'customer_advance' when 'hub_receipt' then 'cash_handover' end
    when 'payroll_payments' then 'salary_payment'
    when 'employee_advances' then case when r ->> 'mode' in ('cash', 'bank', 'mobile') then 'salary_advance' end
    when 'partner_capital' then case when r ->> 'mode' <> 'in_kind' then 'partner_capital' end
    when 'partner_settlement_payments' then 'partner_payout'
    when 'entries' then case when r ->> 'form_code' = '10-2' then 'expense_10_2' end end $$;
create or replace function public._m_dir(p_tbl text, r jsonb) returns text language sql immutable as $$
  select case p_tbl when 'supplier_refunds' then 'in'
    when 'cash_moves' then case when r ->> 'kind' in ('owner_topup', 'cust_advance', 'hub_receipt') then 'in' else 'out' end
    when 'partner_capital' then case when r ->> 'kind' in ('contribution', 'loan_in') then 'in' else 'out' end
    else 'out' end $$;
create or replace function public._m_amount(p_tbl text, r jsonb) returns numeric language sql immutable as $$
  select coalesce(case when p_tbl = 'sale_returns' then (r ->> 'refund_amount')::numeric end, (r ->> 'amount')::numeric, 0) $$;
create or replace function public._m_date(p_tbl text, r jsonb) returns date language sql immutable as $$
  select coalesce((case p_tbl when 'supplier_payments' then r ->> 'paid_at' when 'supplier_refunds' then r ->> 'refunded_at' when 'sale_returns' then r ->> 'created_at' end)::timestamptz at time zone 'Asia/Dhaka',
                  now() at time zone 'Asia/Dhaka')::date $$;

-- ---------- the BEFORE INSERT trigger: resolve the source, check it, set mode, strip the tag ----------
create or replace function public._m_src_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare r jsonb := to_jsonb(new); tagcol text := tg_argv[0]; ev text; st public.money_event_settings; ac bigint; rest text; a public.money_accounts; usr boolean := auth.uid() is not null;
  dflt boolean := false; rowmode text; cl uuid; loc int; amt numeric; md text; dt date;
begin
  select u.acc, u.rest into ac, rest from public._m_untag(r ->> tagcol) u;
  if ac is not null then new := jsonb_populate_record(new, jsonb_build_object(tagcol, rest)); r := to_jsonb(new); end if;
  ev := public._m_event(tg_table_name, r);
  if ev is null then return new; end if;
  select * into st from public.money_event_settings where event_type = ev;
  rowmode := coalesce(r ->> 'mode', r ->> 'refund_mode');
  cl := coalesce(nullif(r ->> 'client_id', '')::uuid, nullif(r ->> 'client_batch', '')::uuid);
  loc := nullif(r ->> 'location_id', '')::int;
  amt := public._m_amount(tg_table_name, r); dt := public._m_date(tg_table_name, r);
  if ac is null and st.default_account_id is not null then
    select * into a from public.money_accounts where id = st.default_account_id and active;
    if found and (rowmode is null or rowmode = public._m_mode_of_kind(a.kind) or (a.kind = 'bank' and rowmode = 'card')) and (a.location_id is null or loc is null or a.location_id = loc) then
      ac := a.id; dflt := true;
    end if;
  end if;
  if ac is null then
    if st.require_source and usr and not public._m_grant_take('require_source', ev, cl, null, amt, dt, tg_table_name) then raise exception 'money_source_required'; end if;
    return new;                                                      -- no source: today's behaviour (generic cash / bank / mobile account by mode)
  end if;
  select * into a from public.money_accounts where id = ac;
  if not found then raise exception 'unknown_money_account'; end if;
  if not a.active then raise exception 'money_account_inactive'; end if;
  if usr and not dflt and st.default_account_id is not null and ac <> st.default_account_id and not st.allow_override
     and not public._m_grant_take('override', ev, cl, ac, amt, dt, tg_table_name) then raise exception 'money_source_fixed'; end if;
  if usr and a.location_id is not null and loc is not null and a.location_id <> loc and not public._m_grant_take('override', ev, cl, ac, amt, dt, tg_table_name) then raise exception 'money_account_place'; end if;
  if ev = 'cash_handover' and a.kind <> 'cash' then raise exception 'money_account_kind'; end if;
  md := public._m_mode_of_kind(a.kind);
  new := jsonb_populate_record(new, jsonb_build_object('mode', md, 'refund_mode', case when a.kind = 'bank' then 'card' else md end, 'money_account_id', ac, 'wallet', null));
  if usr and public._m_dir(tg_table_name, r) = 'out' and amt > 0 then perform public._m_neg_check(ac, amt, ev, cl, dt, tg_table_name); end if;
  return new;
end $$;

create or replace function public._m_src_bu() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.money_account_id is distinct from old.money_account_id then raise exception 'money_account_fixed'; end if;
  return new;
end $$;

-- 10-2 expense voucher: the source is the key money_account_id inside the form data
create or replace function public._m_entries_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare st public.money_event_settings; ac bigint; raw text; a public.money_accounts; usr boolean := auth.uid() is not null; dflt boolean := false; amt numeric; moving boolean;
begin
  if new.form_code <> '10-2' or coalesce(new.data ->> 'from_quick', '') = 'true' or coalesce(current_setting('bos.shadow_create', true), '') = '1' then return new; end if;   -- a shadow made from quick expenses is not a payment
  raw := nullif(btrim(new.data ->> 'money_account_id'), '');
  ac := public._m_id(raw);
  if raw is not null and ac is null then raise exception 'unknown_money_account'; end if;
  select * into st from public.money_event_settings where event_type = 'expense_10_2';
  moving := new.status in ('submitted', 'approved') and (tg_op = 'INSERT' or old.status is distinct from new.status);
  if ac is null and st.default_account_id is not null and new.status in ('draft', 'submitted') then
    select * into a from public.money_accounts where id = st.default_account_id and active;
    if found and (a.location_id is null or a.location_id = new.location_id) then
      ac := a.id; dflt := true; new.data := new.data || jsonb_build_object('money_account_id', ac);
    end if;
  end if;
  if ac is null then
    if moving and st.require_source and usr and not public._m_grant_take('require_source', 'expense_10_2', new.client_id, null, null, new.entry_date, 'entries') then raise exception 'money_source_required'; end if;
    return new;
  end if;
  if tg_op = 'UPDATE' and old.data ->> 'money_account_id' is not distinct from new.data ->> 'money_account_id' and not moving then return new; end if;
  select * into a from public.money_accounts where id = ac;
  if not found then raise exception 'unknown_money_account'; end if;
  if not a.active and (tg_op = 'INSERT' or old.data ->> 'money_account_id' is distinct from new.data ->> 'money_account_id') then raise exception 'money_account_inactive'; end if;
  amt := public._m_voucher_total(new.data);
  if usr and not dflt and st.default_account_id is not null and ac <> st.default_account_id and not st.allow_override
     and not public._m_grant_take('override', 'expense_10_2', new.client_id, ac, amt, new.entry_date, 'entries') then raise exception 'money_source_fixed'; end if;
  if usr and a.location_id is not null and a.location_id <> new.location_id and not public._m_grant_take('override', 'expense_10_2', new.client_id, ac, amt, new.entry_date, 'entries') then raise exception 'money_account_place'; end if;
  if usr and moving and new.status = 'submitted' and amt > 0 then perform public._m_neg_check(ac, amt, 'expense_10_2', new.client_id, new.entry_date, 'entries'); end if;
  return new;
end $$;

do $trg$ declare r record; begin
  for r in select * from (values ('supplier_payments', 'wallet'), ('supplier_refunds', 'wallet'), ('sale_returns', 'wallet'), ('quick_expenses', 'note'), ('cash_moves', 'ref'),
                                 ('payroll_payments', 'ref'), ('employee_advances', 'note'), ('partner_capital', 'ref'), ('partner_settlement_payments', 'ref')) v(t, c) loop
    execute format('drop trigger if exists aa87_money_src_bi on public.%I', r.t);
    execute format('create trigger aa87_money_src_bi before insert on public.%I for each row execute function public._m_src_bi(%L)', r.t, r.c);
    if r.t not in ('partner_settlement_payments') then
      execute format('drop trigger if exists aa87_money_src_bu on public.%I', r.t);
      execute format('create trigger aa87_money_src_bu before update on public.%I for each row execute function public._m_src_bu()', r.t);
    end if;
  end loop;
end $trg$;
drop trigger if exists aa87_money_entries_bi on public.entries;
create trigger aa87_money_entries_bi before insert or update on public.entries for each row when (new.form_code = '10-2') execute function public._m_entries_bi();

-- ============================================================================
-- PART C: registry API (add / rename / deactivate / settings / pick list / exceptions)
-- ============================================================================
create or replace function public.money_account_add(p_kind text, p_name_en text, p_name_bn text default null, p_provider text default null, p_branch text default null,
  p_account_no text default null, p_location int default null, p_coa_code text default null, p_opening numeric default 0, p_opening_date date default null,
  p_neg text default 'warn', p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_coa public.coa_accounts; v_code text; v_par bigint; n bigint; prefix text; nm text := btrim(coalesce(p_name_en, '')); pv text := nullif(btrim(coalesce(p_provider, '')), '');
  an text := nullif(btrim(coalesce(p_account_no, '')), ''); gen text;
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('cash', 'wallet', 'bank') then raise exception 'bad_kind'; end if;
  if length(nm) < 1 then raise exception 'name_required'; end if;
  if coalesce(p_neg, 'warn') not in ('warn', 'block', 'allow') then raise exception 'bad_policy'; end if;
  if p_kind in ('wallet', 'bank') and (pv is null or an is null) then raise exception 'provider_and_number_required'; end if;
  if p_kind = 'cash' and p_location is null and p_coa_code is null then raise exception 'place_required'; end if;
  if p_location is not null and (not exists (select 1 from public.locations where id = p_location) or not public.can_loc(p_location)) then raise exception 'bad_location'; end if;
  if p_kind <> 'cash' and p_location is not null then raise exception 'place_only_for_cash'; end if;
  if coalesce(p_opening, 0) < 0 or coalesce(p_opening, 0) > 1000000000000 then raise exception 'bad_amount'; end if;
  if coalesce(p_opening, 0) > 0 and exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null
                                              and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id)) then raise exception 'opening_exists_use_topup'; end if;
  if exists (select 1 from public.money_accounts a where a.active and a.kind = p_kind and lower(coalesce(a.provider, '')) = lower(coalesce(pv, '')) and lower(coalesce(a.account_no, '')) = lower(coalesce(an, ''))
                and coalesce(a.location_id, 0) = coalesce(p_location, 0) and (p_kind <> 'cash' or lower(a.name_en) = lower(nm))) then raise exception 'account_exists'; end if;
  v_id := nextval(pg_get_serial_sequence('public.money_accounts', 'id'));
  if p_coa_code is not null then
    select * into v_coa from public.coa_accounts where code = btrim(p_coa_code);
    if not found then raise exception 'unknown_account'; end if;
    if v_coa.type <> 'asset' or v_coa.is_group or not v_coa.active then raise exception 'coa_not_usable'; end if;
    if exists (select 1 from public.money_accounts where coa_account_id = v_coa.id) then raise exception 'coa_already_mapped'; end if;
    if exists (select 1 from public.d_wallets where coa_account_id = v_coa.id) then raise exception 'coa_is_legacy_wallet'; end if;
    select string_agg(m.key, ',') into gen from public.acct_mappings m where m.account_id = v_coa.id and m.key like 'pay\_%';
    if gen is not null and not ((gen = 'pay_cash' and p_kind = 'cash') or (gen = 'pay_bank' and p_kind = 'bank') or (gen = 'pay_mobile' and p_kind = 'wallet')) then raise exception 'coa_kind_mismatch'; end if;
  else
    prefix := case p_kind when 'cash' then '1110' when 'bank' then '1120' else '1130' end;
    loop
      n := nextval('public.money_account_code_seq'); v_code := prefix || '-' || lpad(n::text, 3, '0');
      exit when not exists (select 1 from public.coa_accounts where code = v_code);
    end loop;
    select id into v_par from public.coa_accounts where code = '1100';
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, parent_id, is_group, is_system, sort, created_by)
      values (v_code, left(coalesce(nullif(btrim(p_name_bn), ''), nm), 120), left(nm, 120), 'asset', 'debit', v_par, false, false, 16, auth.uid()) returning * into v_coa;
  end if;
  insert into public.money_accounts (id, code, kind, name_bn, name_en, provider, branch, account_no, location_id, coa_account_id, neg_policy, opening_amount, opening_date, note, created_by)
    values (v_id, 'MA-' || lpad(v_id::text, 4, '0'), p_kind, left(coalesce(nullif(btrim(p_name_bn), ''), nm), 120), left(nm, 120), left(pv, 80), left(nullif(btrim(coalesce(p_branch, '')), ''), 80), left(an, 40),
      p_location, v_coa.id, coalesce(p_neg, 'warn'), round(coalesce(p_opening, 0), 2), coalesce(p_opening_date, public._acct_start()), left(p_note, 300), auth.uid());
  insert into public.acct_mappings (key, account_id, label_bn, label_en, updated_by) values ('m_acct_' || v_id::text, v_coa.id, left(nm, 100), 'Money account ' || left(nm, 90), auth.uid());
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'money_account_add', 'money_accounts', v_id::text,
      jsonb_build_object('kind', p_kind, 'name', nm, 'coa', v_coa.code, 'existing_coa', p_coa_code is not null, 'opening', round(coalesce(p_opening, 0), 2)));
  return jsonb_build_object('id', v_id, 'code', 'MA-' || lpad(v_id::text, 4, '0'), 'coa_code', v_coa.code, 'coa_account_id', v_coa.id);
end $$;

create or replace function public.money_account_update(p_id bigint, p_name_en text default null, p_name_bn text default null, p_provider text default null, p_branch text default null,
  p_account_no text default null, p_neg text default null, p_sort int default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.money_accounts;
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  select * into a from public.money_accounts where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if p_neg is not null and p_neg not in ('warn', 'block', 'allow') then raise exception 'bad_policy'; end if;
  if a.kind <> 'cash' and ((p_provider is not null and nullif(btrim(p_provider), '') is null) or (p_account_no is not null and nullif(btrim(p_account_no), '') is null)) then raise exception 'provider_and_number_required'; end if;
  update public.money_accounts set name_en = coalesce(nullif(btrim(p_name_en), ''), name_en), name_bn = coalesce(nullif(btrim(p_name_bn), ''), nullif(btrim(p_name_en), ''), name_bn),
    provider = coalesce(left(nullif(btrim(p_provider), ''), 80), provider), branch = coalesce(left(nullif(btrim(p_branch), ''), 80), branch),
    account_no = coalesce(left(nullif(btrim(p_account_no), ''), 40), account_no), neg_policy = coalesce(p_neg, neg_policy), sort = coalesce(p_sort, sort), note = coalesce(left(p_note, 300), note)
   where id = a.id;
  -- the chart account follows the name (code, type and side never change)
  update public.coa_accounts c set name_en = m.name_en, name_bn = m.name_bn from public.money_accounts m
   where m.id = a.id and c.id = m.coa_account_id and not exists (select 1 from public.acct_mappings k where k.account_id = c.id and k.key like 'pay\_%');
  return jsonb_build_object('id', a.id);
end $$;

create or replace function public.money_account_set_active(p_id bigint, p_active boolean, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.money_accounts; ev text; pr jsonb;
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  select * into a from public.money_accounts where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if p_active is null or p_active = a.active then return jsonb_build_object('id', a.id, 'active', a.active); end if;
  if p_active then
    update public.money_accounts set active = true, deactivated_by = null, deactivated_at = null, deactivate_reason = null where id = a.id;
    update public.coa_accounts set active = true where id = a.coa_account_id;
  else
    if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
    pr := public._m_prove(a.id);
    if abs(coalesce((pr ->> 'journal')::numeric, 0)) > 0.004 or abs(coalesce((pr ->> 'register')::numeric, 0)) > 0.004 then raise exception 'account_not_empty' using detail = 'balance ' || (pr ->> 'register'); end if;
    if coalesce((pr ->> 'pending_n')::int, 0) > 0 then raise exception 'account_has_unposted'; end if;
    select string_agg(event_type, ',') into ev from public.money_event_settings where default_account_id = a.id;
    if ev is not null then raise exception 'account_is_default' using detail = ev; end if;
    if exists (select 1 from public.money_recurring r where r.active and (r.from_account = a.id or r.to_account = a.id)) then raise exception 'account_in_recurring'; end if;
    update public.money_accounts set active = false, deactivated_by = auth.uid(), deactivated_at = now(), deactivate_reason = left(btrim(p_reason), 300) where id = a.id;
    update public.coa_accounts set active = false where id = a.coa_account_id and not exists (select 1 from public.acct_mappings k where k.account_id = a.coa_account_id and k.key like 'pay\_%');
  end if;
  return jsonb_build_object('id', a.id, 'active', p_active);
end $$;

create or replace function public.money_accounts_list(p_asof date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_asof, public._acct_today());
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('ready', public._m_accounting_ready(), 'as_of', d, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'code', a.code, 'kind', a.kind, 'name_en', a.name_en, 'name_bn', a.name_bn, 'provider', a.provider, 'branch', a.branch, 'account_no', a.account_no,
      'location_id', a.location_id, 'coa_code', c.code, 'coa_account_id', a.coa_account_id, 'neg_policy', a.neg_policy, 'active', a.active, 'sort', a.sort,
      'opening_amount', a.opening_amount, 'opening_posted', a.opening_posted, 'generic', public._m_is_generic(a.id), 'note', a.note,
      'journal', public._m_journal_bal(a.id, d), 'book', public._m_reg(a.id), 'pending', (public._m_prove(a.id) ->> 'pending')::numeric,
      'is_default_for', coalesce((select jsonb_agg(s.event_type) from public.money_event_settings s where s.default_account_id = a.id), '[]'::jsonb)) order by a.active desc, a.sort, a.id)
    from public.money_accounts a join public.coa_accounts c on c.id = a.coa_account_id), '[]'::jsonb),
    'legacy_wallets', coalesce((select jsonb_agg(jsonb_build_object('code', w.code, 'name_en', w.name_en, 'coa_code', c.code)) from public.d_wallets w join public.coa_accounts c on c.id = w.coa_account_id), '[]'::jsonb));
end $$;

create or replace function public.money_pick(p_event text, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st public.money_event_settings; seeall boolean := public._m_view();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into st from public.money_event_settings where event_type = p_event;
  if not found then raise exception 'unknown_event'; end if;
  return jsonb_build_object('event', st.event_type, 'default_id', st.default_account_id, 'allow_override', st.allow_override, 'require_source', st.require_source,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'kind', a.kind, 'name_en', a.name_en, 'provider', a.provider, 'location_id', a.location_id,
        'account_no', case when seeall then a.account_no else right(coalesce(a.account_no, ''), 4) end, 'is_default', a.id = st.default_account_id, 'mode', public._m_mode_of_kind(a.kind)) order by a.sort, a.id)
      from public.money_accounts a where a.active and (a.location_id is null or p_loc is null or a.location_id = p_loc)
        and (st.allow_override or st.default_account_id is null or a.id = st.default_account_id)
        and (p_event <> 'cash_handover' or a.kind = 'cash')), '[]'::jsonb));
end $$;

create or replace function public.money_event_settings_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('event_type', s.event_type, 'label_en', s.label_en, 'dir', s.dir, 'default_account_id', s.default_account_id,
    'default_name', a.name_en, 'allow_override', s.allow_override, 'require_source', s.require_source) order by s.sort) from public.money_event_settings s left join public.money_accounts a on a.id = s.default_account_id), '[]'::jsonb);
end $$;

create or replace function public.money_event_setting_set(p_event text, p_default bigint, p_allow_override boolean, p_require boolean, p_clear_default boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.money_event_settings; a public.money_accounts; nd bigint;
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  select * into s from public.money_event_settings where event_type = p_event for update;
  if not found then raise exception 'unknown_event'; end if;
  nd := case when coalesce(p_clear_default, false) then null else coalesce(p_default, s.default_account_id) end;
  if nd is not null then
    select * into a from public.money_accounts where id = nd;
    if not found or not a.active then raise exception 'money_account_inactive'; end if;
    if p_event = 'cash_handover' and a.kind <> 'cash' then raise exception 'money_account_kind'; end if;
  end if;
  update public.money_event_settings set default_account_id = nd, allow_override = coalesce(p_allow_override, allow_override), require_source = coalesce(p_require, require_source),
    updated_by = auth.uid(), updated_at = now() where event_type = p_event;
  return jsonb_build_object('event_type', p_event, 'default_account_id', nd);
end $$;

-- ---------- exceptions ----------
create or replace function public.money_exception_grant(p_rule text, p_reason text, p_for_user uuid default null, p_client uuid default null, p_event text default null,
  p_account bigint default null, p_max numeric default null, p_date date default null, p_hours int default 24) returns jsonb
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_rule is null or p_rule not in ('negative', 'require_source', 'override', 'period_lock', 'approver') then raise exception 'bad_rule'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_for_user is null and p_client is null then raise exception 'target_required'; end if;
  if p_for_user is not null and not exists (select 1 from public.profiles where id = p_for_user and status = 'active') then raise exception 'unknown_user'; end if;
  insert into public.money_exception_grants (rule, event_type, for_user, client_id, account_id, max_amount, on_date, reason, granted_by, expires_at)
    values (p_rule, p_event, p_for_user, p_client, p_account, p_max, p_date, left(btrim(p_reason), 300), auth.uid(), now() + make_interval(hours => least(greatest(coalesce(p_hours, 24), 1), 168))) returning id into id_;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'money_exception_grant', 'money_exception_grants', id_::text,
      jsonb_build_object('rule', p_rule, 'event', p_event, 'for_user', p_for_user, 'client', p_client, 'account', p_account, 'max', p_max, 'date', p_date, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('id', id_);
end $$;

create or replace function public.money_exception_revoke(p_id bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  update public.money_exception_grants set revoked = true where id = p_id and used_at is null;
  if not found then raise exception 'not found'; end if;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'money_exception_revoke', 'money_exception_grants', p_id::text, jsonb_build_object('note', left(p_note, 200)));
  return jsonb_build_object('id', p_id, 'revoked', true);
end $$;

create or replace function public.money_exceptions_list(p_status text default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
      select x.id, x.at, x.kind, x.event_type, x.account_id, a.name_en as account_name, x.amount, x.src_table, x.src_id, x.reason, x.status, x.resolve_note, x.resolved_at
        from public.money_exceptions x left join public.money_accounts a on a.id = x.account_id where p_status is null or x.status = p_status order by x.id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z), '[]'::jsonb),
    'grants', case when public.is_owner() then coalesce((select jsonb_agg(to_jsonb(g) order by g.id desc) from (select * from public.money_exception_grants order by id desc limit 100) g), '[]'::jsonb) else '[]'::jsonb end);
end $$;

create or replace function public.money_exception_resolve(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  update public.money_exceptions set status = 'resolved', resolved_by = auth.uid(), resolved_at = now(), resolve_note = left(btrim(p_note), 300) where id = p_id and status = 'open';
  if not found then raise exception 'not found'; end if;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'money_exception_resolve', 'money_exceptions', p_id::text, jsonb_build_object('note', left(btrim(p_note), 300)));
  return jsonb_build_object('id', p_id, 'status', 'resolved');
end $$;

-- period lock: an owner granted one-off exception (rule period_lock). lock_check is patched to ask this; the grant is used once per transaction.
create or replace function public._m_lock_exc(p_date date) returns boolean language plpgsql security definer set search_path = public as $$
declare g public.money_exception_grants; cur text := coalesce(current_setting('bos87.lockx', true), '');
begin
  if auth.uid() is null then return false; end if;
  if cur <> '' then return true; end if;
  select * into g from public.money_exception_grants x
   where x.rule = 'period_lock' and not x.revoked and x.used_at is null and x.expires_at > now() and x.for_user = auth.uid() and (x.on_date is null or x.on_date = p_date)
   order by x.id limit 1 for update skip locked;
  if not found then return false; end if;
  update public.money_exception_grants set used_at = now(), used_ref = 'lock ' || p_date::text where id = g.id;
  perform set_config('bos87.lockx', g.id::text, true);
  insert into public.money_exceptions (kind, reason, amount, src_id, by_user) values ('period_lock_exception', g.reason || ' (date ' || p_date::text || ')', null, 'lock_check', auth.uid());
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'money_exception_used', 'money_exception_grants', g.id::text,
      jsonb_build_object('rule', 'period_lock', 'date', p_date, 'reason', g.reason, 'granted_by', g.granted_by));
  return true;
end $$;

-- ============================================================================
-- PART D: transfers, charges, recurring
-- ============================================================================
create or replace function public._m_transfer_core(p_from bigint, p_to bigint, p_amount numeric, p_date date, p_fee numeric, p_fee_side text, p_ref text, p_note text, p_loc int, p_client uuid, p_rec bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare f public.money_accounts; t public.money_accounts; t0 public.money_transfers; amt numeric := round(p_amount, 2); fee numeric := round(coalesce(p_fee, 0), 2); loc int; sid text; id_ bigint;
begin
  if p_from is null or p_to is null or p_from = p_to then raise exception 'same_account'; end if;
  if amt is null or amt <= 0 or amt > 1000000000 then raise exception 'bad_amount'; end if;
  if fee < 0 or fee > 1000000000 then raise exception 'bad_amount'; end if;
  if coalesce(p_fee_side, 'from') not in ('from', 'to') then raise exception 'bad_kind'; end if;
  if p_date is null or p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  if coalesce(p_fee_side, 'from') = 'to' and fee > amt then raise exception 'fee_exceeds_amount'; end if;
  perform public.lock_check(p_date);
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into t0 from public.money_transfers where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', t0.id); end if;
  end if;
  select * into f from public.money_accounts where id = least(p_from, p_to) for update;      -- fixed lock order
  select * into t from public.money_accounts where id = greatest(p_from, p_to) for update;
  select * into f from public.money_accounts where id = p_from; select * into t from public.money_accounts where id = p_to;
  if f.id is null or t.id is null then raise exception 'unknown_money_account'; end if;
  if not f.active or not t.active then raise exception 'money_account_inactive'; end if;
  loc := coalesce(p_loc, f.location_id, t.location_id);
  if p_loc is not null and ((f.location_id is not null and f.location_id <> p_loc) or (t.location_id is not null and t.location_id <> p_loc)) and auth.uid() is not null then raise exception 'money_account_place'; end if;
  if loc is null then raise exception 'place_required'; end if;
  if not public.can_loc(loc) then raise exception 'not allowed for this location'; end if;
  if auth.uid() is not null then
    perform public._m_neg_check(f.id, amt + case when coalesce(p_fee_side, 'from') = 'from' then fee else 0 end, 'money_transfer', p_client, p_date, 'money_transfers');
    if coalesce(p_fee_side, 'from') = 'to' and fee > 0 then null; end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.money_transfers (client_id, from_account, to_account, amount, fee, fee_side, xfer_date, location_id, ref, note, recurring_id, created_by, created_staff)
    values (p_client, p_from, p_to, amt, fee, coalesce(p_fee_side, 'from'), p_date, loc, left(nullif(btrim(p_ref), ''), 60), left(nullif(btrim(p_note), ''), 200), p_rec, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'from_balance', public._m_reg(p_from), 'to_balance', public._m_reg(p_to));
end $$;

create or replace function public.money_transfer_add(p_from bigint, p_to bigint, p_amount numeric, p_date date, p_fee numeric default 0, p_fee_side text default 'from',
  p_ref text default null, p_note text default null, p_loc int default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not (public._m_mgr() or public._d_cash_ok(p_loc)) then raise exception 'not allowed'; end if;
  return public._m_transfer_core(p_from, p_to, p_amount, p_date, p_fee, p_fee_side, p_ref, p_note, p_loc, p_client, null);
end $$;

create or replace function public.money_transfer_void(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.money_transfers;
begin
  select * into t from public.money_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not (public._m_mgr() or public._d_cash_ok(t.location_id)) then raise exception 'not allowed'; end if;
  if t.status = 'void' then raise exception 'already_void'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  perform public.lock_check(t.xfer_date);
  perform public._m_neg_check(t.to_account, t.amount - case when t.fee_side = 'to' then t.fee else 0 end, 'money_transfer_void', null, t.xfer_date, 'money_transfers');
  update public.money_transfers set status = 'void', void_note = left(btrim(p_note), 200), void_by = auth.uid(), void_at = now() where id = t.id;
  return jsonb_build_object('id', t.id, 'voided', true);
end $$;

create or replace function public.money_charge_add(p_account bigint, p_kind text, p_amount numeric, p_date date, p_ref text default null, p_note text default null, p_loc int default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.money_accounts; amt numeric := round(p_amount, 2); c0 public.money_charges; id_ bigint; sid text;
begin
  if not (public._m_mgr() or public._d_cash_ok(p_loc)) then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('charge', 'interest') then raise exception 'bad_kind'; end if;
  if amt is null or amt <= 0 or amt > 1000000000 then raise exception 'bad_amount'; end if;
  if p_date is null or p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  perform public.lock_check(p_date);
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into c0 from public.money_charges where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', c0.id); end if;
  end if;
  select * into a from public.money_accounts where id = p_account;
  if not found then raise exception 'unknown_money_account'; end if;
  if not a.active then raise exception 'money_account_inactive'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_kind = 'charge' then perform public._m_neg_check(a.id, amt, 'money_charge', p_client, p_date, 'money_charges'); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.money_charges (client_id, account_id, kind, amount, charge_date, location_id, ref, note, created_by, created_staff)
    values (p_client, a.id, p_kind, amt, p_date, coalesce(p_loc, a.location_id), left(nullif(btrim(p_ref), ''), 60), left(nullif(btrim(p_note), ''), 200), auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'balance', public._m_reg(a.id));
end $$;

create or replace function public.money_charge_void(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.money_charges;
begin
  select * into c from public.money_charges where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not (public._m_mgr() or public._d_cash_ok(c.location_id)) then raise exception 'not allowed'; end if;
  if c.status = 'void' then raise exception 'already_void'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  perform public.lock_check(c.charge_date);
  if c.kind = 'interest' then perform public._m_neg_check(c.account_id, c.amount, 'money_charge_void', null, c.charge_date, 'money_charges'); end if;
  update public.money_charges set status = 'void', void_note = left(btrim(p_note), 200), void_by = auth.uid(), void_at = now() where id = c.id;
  return jsonb_build_object('id', c.id, 'voided', true);
end $$;

create or replace function public.money_recurring_add(p_name text, p_from bigint, p_to bigint, p_amount numeric, p_day int, p_start date, p_end date default null, p_fee numeric default 0, p_fee_side text default 'from', p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  if p_from = p_to then raise exception 'same_account'; end if;
  if not exists (select 1 from public.money_accounts where id = p_from and active) or not exists (select 1 from public.money_accounts where id = p_to and active) then raise exception 'money_account_inactive'; end if;
  insert into public.money_recurring (name, from_account, to_account, amount, fee, fee_side, day_of_month, start_date, end_date, location_id, created_by)
    values (p_name, p_from, p_to, round(p_amount, 2), round(coalesce(p_fee, 0), 2), coalesce(p_fee_side, 'from'), p_day, p_start, p_end, p_loc, auth.uid()) returning id into id_;
  return jsonb_build_object('id', id_);
end $$;

create or replace function public.money_recurring_set_active(p_id bigint, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  update public.money_recurring set active = coalesce(p_active, active) where id = p_id;
  if not found then raise exception 'not found'; end if;
  return jsonb_build_object('id', p_id, 'active', p_active);
end $$;

create or replace function public.money_recurring_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(r) order by r.id) from public.money_recurring r), '[]'::jsonb);
end $$;

-- creates the transfers that are due up to p_date (once each: the client id is derived from the template and the due date)
create or replace function public.money_recurring_run(p_date date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d date := coalesce(p_date, public._acct_today()); r public.money_recurring; due date; made int := 0; errs jsonb := '[]'; cid uuid;
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  for r in select * from public.money_recurring where active order by id loop
    due := make_date(extract(year from d)::int, extract(month from d)::int, r.day_of_month);
    if d < due or due < r.start_date or (r.end_date is not null and due > r.end_date) or (r.last_run is not null and r.last_run >= due) then continue; end if;
    cid := md5('money_recurring:' || r.id::text || ':' || due::text)::uuid;
    begin
      perform public._m_transfer_core(r.from_account, r.to_account, r.amount, due, r.fee, r.fee_side, 'REC-' || r.id::text, r.name, r.location_id, cid, r.id);
      update public.money_recurring set last_run = due where id = r.id;
      made := made + 1;
    exception when others then errs := errs || jsonb_build_object('recurring_id', r.id, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('date', d, 'made', made, 'errors', errs);
end $$;

-- ============================================================================
-- PART E: journal sources, day book rows, statements, summary, real balance check, reports, balance check
-- ============================================================================
-- journal sources of this phase, same shape as _acct_docs (hooked in by the patch below)
create or replace function public._m_docs(p_start date)
returns table(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  -- a transfer: Dr receiving account, Cr paying account; the fee (if any) is its own expense line against the account that bears it. One balanced entry.
  return query
  select 'money_transfer'::text, t.id::text, t.xfer_date, t.location_id, ('Transfer ' || fa.name_en || ' to ' || ta.name_en)::text, null::text, t.status = 'done',
    coalesce((t.void_at at time zone 'Asia/Dhaka')::date, public._acct_today()), null::text, null::text,
    case when t.status = 'done' then
      jsonb_build_array(jsonb_build_object('a', 'm_acct_' || t.to_account::text, 'd', t.amount), jsonb_build_object('a', 'm_acct_' || t.from_account::text, 'c', t.amount))
      || case when t.fee > 0 then jsonb_build_array(
           jsonb_build_object('a', case when (case t.fee_side when 'from' then fa.kind else ta.kind end) = 'wallet' then 'wallet_fee' else 'm_bank_charge' end, 'd', t.fee),
           jsonb_build_object('a', 'm_acct_' || (case t.fee_side when 'from' then t.from_account else t.to_account end)::text, 'c', t.fee)) else '[]'::jsonb end
    end
  from public.money_transfers t join public.money_accounts fa on fa.id = t.from_account join public.money_accounts ta on ta.id = t.to_account
  where t.xfer_date >= p_start and public._acct_need('money_transfer', t.id::text, t.status = 'done');
  -- bank / wallet charge: Dr charge expense, Cr the account. Interest: Dr the account, Cr interest income.
  return query
  select 'money_charge'::text, c.id::text, c.charge_date, c.location_id, ((case c.kind when 'interest' then 'Interest ' else 'Charge ' end) || a.name_en)::text, c.kind, c.status = 'done',
    coalesce((c.void_at at time zone 'Asia/Dhaka')::date, public._acct_today()), null::text, null::text,
    case when c.status = 'done' then case c.kind
      when 'interest' then jsonb_build_array(jsonb_build_object('a', 'm_acct_' || c.account_id::text, 'd', c.amount), jsonb_build_object('a', 'm_interest_income', 'c', c.amount))
      else jsonb_build_array(jsonb_build_object('a', case a.kind when 'wallet' then 'wallet_fee' else 'm_bank_charge' end, 'd', c.amount), jsonb_build_object('a', 'm_acct_' || c.account_id::text, 'c', c.amount)) end end
  from public.money_charges c join public.money_accounts a on a.id = c.account_id
  where c.charge_date >= p_start and public._acct_need('money_charge', c.id::text, c.status = 'done');
end $$;

-- day book rows for transfers and charges (same columns as _daybook_lines); both sides of a transfer are shown, one per account mode
create or replace function public._m_daybook_rows(p_locs int[], p_from date, p_to date)
returns table(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
language sql stable security definer set search_path = public as $$
  select t.location_id, t.xfer_date, 'out'::text, public._m_mode_of_kind(fa.kind), 'money_transfer'::text, t.amount + case when t.fee_side = 'from' then t.fee else 0 end, t.ref,
         nullif(btrim(concat_ws(' · ', 'to ' || ta.name_en, case when t.fee > 0 then 'fee ' || t.fee::text end, fa.name_en, t.note)), ''), t.created_staff, t.created_at, 'money_transfer'::text, t.id::text, false, false
    from public.money_transfers t join public.money_accounts fa on fa.id = t.from_account join public.money_accounts ta on ta.id = t.to_account
   where t.status = 'done' and t.location_id = any (p_locs) and t.xfer_date between p_from and p_to
  union all
  select t.location_id, t.xfer_date, 'in', public._m_mode_of_kind(ta.kind), 'money_transfer', t.amount - case when t.fee_side = 'to' then t.fee else 0 end, t.ref,
         nullif(btrim(concat_ws(' · ', 'from ' || fa.name_en, ta.name_en, t.note)), ''), t.created_staff, t.created_at, 'money_transfer', t.id::text, false, false
    from public.money_transfers t join public.money_accounts fa on fa.id = t.from_account join public.money_accounts ta on ta.id = t.to_account
   where t.status = 'done' and t.location_id = any (p_locs) and t.xfer_date between p_from and p_to
  union all
  select c.location_id, c.charge_date, case c.kind when 'interest' then 'in' else 'out' end, public._m_mode_of_kind(a.kind), 'money_charge', c.amount, c.ref,
         nullif(btrim(concat_ws(' · ', a.name_en, c.kind, c.note)), ''), c.created_staff, c.created_at, 'money_charge', c.id::text, false, false
    from public.money_charges c join public.money_accounts a on a.id = c.account_id
   where c.status = 'done' and c.location_id = any (p_locs) and c.charge_date between p_from and p_to $$;

create or replace function public._m_csv(t text) returns text language sql immutable as $$ select '"' || replace(coalesce(t, ''), '"', '""') || '"' $$;

-- ---------- per account statement (opening, in, out, closing for a date range) ----------
create or replace function public.money_statement(p_account bigint, p_from date default null, p_to date default null, p_loc int default null, p_limit int default 2000) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a public.money_accounts; st date := public._acct_start(); v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); fr date; to_ date := coalesce(p_to, public._acct_today());
  open_ numeric; rows_ jsonb; tin numeric; tout numeric; pend jsonb; lim int := least(greatest(coalesce(p_limit, 2000), 1), 5000);
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  select * into a from public.money_accounts where id = p_account;
  if not found then raise exception 'not found'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  fr := coalesce(p_from, st);
  if fr > to_ then raise exception 'bad_range'; end if;
  select coalesce(sum(l.debit - l.credit), 0) into open_ from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
   where l.account_id = a.coa_account_id and e.entry_date < fr and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc);
  select coalesce(sum(l.debit), 0), coalesce(sum(l.credit), 0) into tin, tout from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
   where l.account_id = a.coa_account_id and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc);
  select coalesce(jsonb_agg(jsonb_build_object('date', w.entry_date, 'entry_id', w.entry_id, 'line_no', w.line_no, 'memo', w.memo, 'source_type', w.source_type, 'source_id', w.source_id,
      'counter', w.counter, 'location_id', w.location_id, 'in', w.debit, 'out', w.credit, 'balance', w.bal, 'reversal', w.reverses_id is not null) order by w.entry_date, w.entry_id, w.line_no), '[]'::jsonb)
    into rows_ from (
      select z.*, open_ + sum(z.debit - z.credit) over (order by z.entry_date, z.entry_id, z.line_no) bal from (
        select e.entry_date, e.id entry_id, l.line_no, e.memo, e.source_type, e.source_id, e.reverses_id, l.location_id, l.debit, l.credit,
               (select string_agg(distinct c2.code, ',') from public.journal_lines l2 join public.coa_accounts c2 on c2.id = l2.account_id where l2.entry_id = l.entry_id and l2.account_id <> l.account_id) counter
          from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
         where l.account_id = a.coa_account_id and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
         order by e.entry_date, e.id, l.line_no limit lim) z) w;
  select coalesce(jsonb_agg(jsonb_build_object('date', s.d, 'source', s.tbl, 'id', s.pk, 'event', s.ev, 'amount', s.amt, 'memo', s.memo) order by s.d), '[]'::jsonb) into pend
    from public._m_src(a.id) s
   where s.live and s.d between fr and to_ and not exists (select 1 from public.journal_entries e where e.source_type = s.jtype and e.source_id = s.jid and e.reverses_id is null);
  return jsonb_build_object('account', jsonb_build_object('id', a.id, 'code', a.code, 'kind', a.kind, 'name_en', a.name_en, 'provider', a.provider, 'account_no', a.account_no, 'active', a.active),
    'from', fr, 'to', to_, 'opening', open_, 'in', tin, 'out', tout, 'closing', open_ + tin - tout, 'rows', rows_, 'not_posted_yet', pend,
    'truncated', jsonb_array_length(rows_) >= lim);
end $$;

create or replace function public.money_statement_csv(p_account bigint, p_from date default null, p_to date default null, p_loc int default null) returns text
language plpgsql stable security definer set search_path = public as $$
declare s jsonb := public.money_statement(p_account, p_from, p_to, p_loc, 5000); out_ text; r jsonb;
begin
  if s ? 'data_needed' then return 'data_needed'; end if;
  out_ := 'Statement,' || public._m_csv(s #>> '{account,name_en}') || E'\nFrom,' || (s ->> 'from') || E'\nTo,' || (s ->> 'to') || E'\nOpening,' || (s ->> 'opening') || E'\n' ||
          'date,entry,source,memo,counter account,in,out,balance' || E'\n';
  for r in select * from jsonb_array_elements(s -> 'rows') loop
    out_ := out_ || (r ->> 'date') || ',' || (r ->> 'entry_id') || ',' || public._m_csv(r ->> 'source_type') || ',' || public._m_csv(r ->> 'memo') || ',' || public._m_csv(r ->> 'counter') || ',' ||
            (r ->> 'in') || ',' || (r ->> 'out') || ',' || (r ->> 'balance') || E'\n';
  end loop;
  return out_ || 'Totals,,,,,' || (s ->> 'in') || ',' || (s ->> 'out') || ',' || (s ->> 'closing') || E'\n';
end $$;

-- ---------- period summary across all accounts (opening, in, out, closing per account; per day totals) ----------
create or replace function public.money_summary(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); fr date; to_ date := coalesce(p_to, public._acct_today()); rows_ jsonb; days_ jsonb; tot jsonb;
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  fr := coalesce(p_from, st);
  if fr > to_ then raise exception 'bad_range'; end if;
  with b as (
    select a.id, a.code, a.kind, a.name_en, a.active,
      coalesce(sum(l.debit - l.credit) filter (where e.entry_date < fr), 0) op,
      coalesce(sum(l.debit) filter (where e.entry_date between fr and to_), 0) din,
      coalesce(sum(l.credit) filter (where e.entry_date between fr and to_), 0) dout,
      coalesce(sum(l.debit - l.credit) filter (where e.entry_date <= to_), 0) cl
    from public.money_accounts a
    left join public.journal_lines l on l.account_id = a.coa_account_id and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
    left join public.journal_entries e on e.id = l.entry_id
    group by a.id, a.code, a.kind, a.name_en, a.active, a.sort order by a.sort, a.id)
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'code', code, 'kind', kind, 'name_en', name_en, 'active', active, 'opening', op, 'in', din, 'out', dout, 'closing', cl)) filter (where active or op <> 0 or din <> 0 or dout <> 0 or cl <> 0), '[]'::jsonb),
         jsonb_build_object('opening', coalesce(sum(op), 0), 'in', coalesce(sum(din), 0), 'out', coalesce(sum(dout), 0), 'closing', coalesce(sum(cl), 0))
    into rows_, tot from b;
  select coalesce(jsonb_agg(jsonb_build_object('date', d, 'in', i, 'out', o, 'net', i - o) order by d), '[]'::jsonb) into days_ from (
    select e.entry_date d, sum(l.debit) i, sum(l.credit) o from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
      join public.money_accounts a on a.coa_account_id = l.account_id
     where e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc) group by e.entry_date) z;
  return jsonb_build_object('from', fr, 'to', to_, 'accounts', rows_, 'total', tot, 'days', days_,
    'note', 'In and out include transfers between your own accounts (they cancel in the total).');
end $$;

-- ---------- the real balance (blind) ----------
create or replace function public._m_book(p_acc bigint, p_asof date) returns numeric language sql stable security definer set search_path = public as $$
  select public._m_journal_bal(p_acc, p_asof) + case when public._m_is_generic(p_acc) then 0 else coalesce((select sum(s.amt) from public._m_src(p_acc) s
      where s.live and s.d <= p_asof and not exists (select 1 from public.journal_entries e where e.source_type = s.jtype and e.source_id = s.jid and e.reverses_id is null)), 0) end $$;

create or replace function public.money_check_save(p_account bigint, p_date date, p_real numeric, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.money_accounts; c public.money_checks; book numeric; df numeric; real_ numeric := round(p_real, 2); sid text; ex bigint;
begin
  select * into a from public.money_accounts where id = p_account;
  if not found then raise exception 'not found'; end if;
  if not (public._m_mgr() or public._d_cash_ok(a.location_id)) then raise exception 'not allowed'; end if;
  if real_ is null or real_ < 0 or real_ > 1000000000000 then raise exception 'bad_amount'; end if;
  if p_date is null or p_date > public._acct_today() then raise exception 'bad_date'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into c from public.money_checks where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', c.id, 'book', c.book_balance, 'diff', c.diff, 'status', c.status); end if;
  end if;
  book := public._m_book(a.id, p_date); df := round(real_ - book, 2);
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.money_checks (account_id, check_date, real_balance, book_balance, diff, status, client_id, counted_by, counted_staff)
    values (a.id, p_date, real_, book, df, case when df = 0 then 'matched' else 'difference' end, p_client, auth.uid(), sid) returning * into c;
  if df <> 0 then
    insert into public.money_exceptions (kind, account_id, amount, src_table, src_id, reason, by_user) values ('recon_diff', a.id, df, 'money_checks', c.id::text, 'real ' || real_::text || ' book ' || book::text, auth.uid());
  end if;
  return jsonb_build_object('id', c.id, 'real', c.real_balance, 'book', c.book_balance, 'diff', c.diff, 'status', c.status);      -- the book figure is shown only now, after the count is saved
end $$;

create or replace function public.money_check_explain(p_check bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.money_checks; a public.money_accounts;
begin
  select * into c from public.money_checks where id = p_check for update;
  if not found then raise exception 'not found'; end if;
  select * into a from public.money_accounts where id = c.account_id;
  if not (public._m_mgr() or public._d_cash_ok(a.location_id)) then raise exception 'not allowed'; end if;
  if c.status <> 'difference' then raise exception 'nothing_to_explain'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  update public.money_checks set reason = left(btrim(p_reason), 300), status = 'explained', reason_by = auth.uid(), reason_at = now() where id = c.id;
  update public.money_exceptions set status = 'resolved', resolved_by = auth.uid(), resolved_at = now(), resolve_note = left(btrim(p_reason), 300)
   where kind = 'recon_diff' and src_table = 'money_checks' and src_id = c.id::text and status = 'open';
  return jsonb_build_object('id', c.id, 'status', 'explained');
end $$;

create or replace function public.money_checks_list(p_account bigint default null, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._m_view() or public._d_cash_ok(null)) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'account_id', k.account_id, 'account', a.name_en, 'date', k.check_date, 'real', k.real_balance, 'book', k.book_balance, 'diff', k.diff,
    'status', k.status, 'reason', k.reason) order by k.id desc) from (select * from public.money_checks where p_account is null or account_id = p_account order by id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) k
    join public.money_accounts a on a.id = k.account_id), '[]'::jsonb);
end $$;

-- ---------- Balance Check item: money accounts total = sum of the mapped ledger accounts ----------
create or replace function public._m_balance_check(p_asof date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; pr jsonb; rows_ jsonb := '[]'; tot_reg numeric := 0; tot_led numeric := 0; bad int := 0; pend int := 0; n int := 0;
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  for r in select a.id, a.code, a.name_en from public.money_accounts a order by a.id loop
    pr := public._m_prove(r.id); n := n + 1;
    tot_reg := tot_reg + (pr ->> 'register')::numeric; tot_led := tot_led + (pr ->> 'journal')::numeric;
    if abs((pr ->> 'diff')::numeric) > 0.004 then bad := bad + 1; end if;
    if abs((pr ->> 'pending')::numeric) > 0.004 or abs((pr ->> 'stale')::numeric) > 0.004 then pend := pend + 1; end if;
    if abs((pr ->> 'diff')::numeric) > 0.004 or abs((pr ->> 'pending')::numeric) > 0.004 or abs((pr ->> 'stale')::numeric) > 0.004 then
      rows_ := rows_ || (pr || jsonb_build_object('code', r.code, 'name_en', r.name_en));
    end if;
  end loop;
  return jsonb_build_object('ran', true, 'accounts', n, 'money_accounts_total', tot_reg, 'ledger_total', tot_led, 'difference', round(tot_reg - tot_led, 2),
    'unexplained_accounts', bad, 'timing_accounts', pend, 'rows', rows_, 'red', bad > 0, 'amber', pend > 0, 'ok', bad = 0 and pend = 0,
    'note', 'Money accounts total = the book balance of every registered account (payments counted when entered). Ledger total = the mapped chart accounts in the journal. A difference that is only a payment not posted yet is timing (amber); a ledger movement that belongs to no payment is red.');
end $$;

-- ---------- reports: P&L and balance sheet with the cash / bank / wallet lines per account ----------
create or replace function public.money_statements(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); to_ date := coalesce(p_to, public._acct_today()); fr date; v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); lines_ jsonb;
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  fr := coalesce(p_from, st);
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', c.code, 'coa_code', c.code, 'name_en', a.name_en, 'kind', a.kind, 'active', a.active,
      'opening', x.op, 'in', x.din, 'out', x.dout, 'closing', x.cl) order by a.kind, a.sort, a.id), '[]'::jsonb) into lines_
    from public.money_accounts a join public.coa_accounts c on c.id = a.coa_account_id
    cross join lateral (select coalesce(sum(l.debit - l.credit) filter (where e.entry_date < fr), 0) op, coalesce(sum(l.debit) filter (where e.entry_date between fr and to_), 0) din,
                               coalesce(sum(l.credit) filter (where e.entry_date between fr and to_), 0) dout, coalesce(sum(l.debit - l.credit) filter (where e.entry_date <= to_), 0) cl
                          from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
                         where l.account_id = a.coa_account_id and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)) x
   where a.active or x.op <> 0 or x.din <> 0 or x.dout <> 0 or x.cl <> 0;
  return jsonb_build_object('from', fr, 'to', to_, 'income_statement', public.acct_income_statement(fr, to_, p_loc), 'balance_sheet', public.acct_balance_sheet(to_, p_loc),
    'money_lines', lines_, 'money_total_closing', (select coalesce(sum((z ->> 'closing')::numeric), 0) from jsonb_array_elements(lines_) z));
end $$;

-- ---------- salary reports show the payment source ----------
create or replace function public.money_salary_sources(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or public._acct_view() or p_loc is not null and public.has_grant('salary_view', p_loc)) then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  return jsonb_build_object('from', p_from, 'to', p_to,
    'payments', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'date', p.pay_date, 'run', p.run_id, 'employee_no', e.employee_no, 'employee', e.full_name_bn, 'amount', p.amount, 'mode', p.mode,
        'money_account_id', p.money_account_id, 'source', coalesce(a.name_en, 'not named (' || p.mode || ')'), 'status', p.status) order by p.pay_date, p.id)
      from public.payroll_payments p join public.employees e on e.id = p.employee_id left join public.money_accounts a on a.id = p.money_account_id
      where p.pay_date between p_from and p_to and (p_loc is null or p.location_id = p_loc) and (public.is_owner() or public.has_grant('salary_view', p.location_id))), '[]'::jsonb),
    'by_source', coalesce((select jsonb_agg(jsonb_build_object('source', s, 'amount', t) order by s) from (
        select coalesce(a.name_en, 'not named (' || p.mode || ')') s, sum(p.amount) t from public.payroll_payments p left join public.money_accounts a on a.id = p.money_account_id
         where p.pay_date between p_from and p_to and p.status = 'done' and (p_loc is null or p.location_id = p_loc) and (public.is_owner() or public.has_grant('salary_view', p.location_id)) group by 1) z), '[]'::jsonb));
end $$;

-- ---------- opening balance: the section "money" of opening_balance_post (phase80) ----------
create or replace function public._m_opening_line(x jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a public.money_accounts;
begin
  select * into a from public.money_accounts where id = public._m_id(x ->> 'money_account_id');
  if not found then raise exception 'unknown_money_account'; end if;
  if not a.active then raise exception 'money_account_inactive'; end if;
  if coalesce(x ->> 'amount', '') !~ '^[0-9]{1,12}(\.[0-9]{1,2})?$' then raise exception 'bad_amount'; end if;
  return jsonb_build_object('a', 'm_acct_' || a.id::text, 'debit', x ->> 'amount', 'memo', left('opening ' || a.name_en, 120), 'location_id', a.location_id);
end $$;
create or replace function public._m_opening_mark(p_json jsonb) returns void language plpgsql security definer set search_path = public as $$
declare x jsonb;
begin
  for x in select * from jsonb_array_elements(coalesce(p_json -> 'money', '[]'::jsonb)) loop
    update public.money_accounts set opening_amount = (x ->> 'amount')::numeric, opening_posted = true, opening_date = coalesce(public._acct_start(), opening_date) where id = public._m_id(x ->> 'money_account_id');
  end loop;
end $$;
-- the "money" section the opening screen should send: every registered account with the opening figure typed on it
create or replace function public.money_opening_json() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('money_account_id', a.id, 'amount', a.opening_amount::text) order by a.id) from public.money_accounts a
                    where a.active and a.opening_amount > 0 and not a.opening_posted), '[]'::jsonb);
end $$;

-- ============================================================================
-- PART F: PATCHES of the shared functions (text patch of the LIVE definition; each site must exist, otherwise the paste stops)
--   _acct_docs / _c_docs : the money line of 14 payment events uses the payment's own account (mapping key m_acct_<id>) when it has one, else exactly what it used before
--   day book (3 functions): 10-2 mode follows the account, the account name is shown in the text of the line, transfers and charges are listed
--   daybook_vs_journal, acct_cash_flow : the money accounts count as cash / bank / mobile accounts
--   _e_balance_check : the new item money_accounts       opening_balance_post : the section "money"       lock_check : owner granted one-off exception
-- ============================================================================
select public._m_patch('public._acct_docs(date)'::regprocedure, array[
  $a$jsonb_build_object('a', public._acct_paykey(p.mode, true), 'c', p.amount)$a$, $a$jsonb_build_object('a', public._m_key(p.money_account_id, public._acct_paykey(p.mode, true)), 'c', p.amount) /* bos87 */$a$,
  $a$jsonb_build_object('a', public._acct_paykey(f.mode, true), 'd', f.amount)$a$, $a$jsonb_build_object('a', public._m_key(f.money_account_id, public._acct_paykey(f.mode, true)), 'd', f.amount) /* bos87 */$a$,
  $a$jsonb_build_object('a', public._acct_paykey(coalesce(r.refund_mode, 'cash')), 'c', r.refund_amount)$a$, $a$jsonb_build_object('a', public._m_key(r.money_account_id, public._acct_paykey(coalesce(r.refund_mode, 'cash'))), 'c', r.refund_amount) /* bos87 */$a$,
  $a$jsonb_build_object('a', 'pay_cash', 'c', v.total)$a$, $a$jsonb_build_object('a', public._m_key(public._m_id(e.data ->> 'money_account_id'), 'pay_cash'), 'c', v.total) /* bos87 */$a$,
  $a$jsonb_build_object('a', public._acct_paykey(q.mode), 'c', q.amount)$a$, $a$jsonb_build_object('a', public._m_key(q.money_account_id, public._acct_paykey(q.mode)), 'c', q.amount) /* bos87 */$a$,
  $a$public._acct_paykey(m.mode)$a$, $a$public._m_key(m.money_account_id, public._acct_paykey(m.mode)) /* bos87 */$a$,
  $a$jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'hub_clearing'$a$, $a$jsonb_build_object('a', public._m_key(m.money_account_id, 'pay_cash'), 'd', m.amount), jsonb_build_object('a', 'hub_clearing'$a$,
  $a$jsonb_build_object('a', public._c_salary_paykey(p.mode), 'c', p.amount /* bos85 */)$a$, $a$jsonb_build_object('a', public._m_key(p.money_account_id, public._c_salary_paykey(p.mode)), 'c', p.amount /* bos85 */)$a$,
  $a$jsonb_build_object('a', public._acct_paykey(a.mode), 'c', a.amount)$a$, $a$jsonb_build_object('a', public._m_key(a.money_account_id, public._acct_paykey(a.mode)), 'c', a.amount)$a$,
  $a$public._acct_paykey(c.mode)$a$, $a$public._m_key(c.money_account_id, public._acct_paykey(c.mode))$a$,
  $a$return query select * from public._d_acct_docs(p_start); /* bos85 */$a$, $a$return query select * from public._d_acct_docs(p_start); /* bos85 */
  return query select * from public._m_docs(p_start); /* bos87: transfers and charges between money accounts */$a$]);

select public._m_patch('public._c_docs(date)'::regprocedure, array[
  $a$jsonb_build_object('a', public._c_salary_paykey(p.mode), 'c', p.amount)$a$, $a$jsonb_build_object('a', public._m_key(p.money_account_id, public._c_salary_paykey(p.mode)), 'c', p.amount) /* bos87 */$a$,
  $a$jsonb_build_object('a', public._acct_paykey(pp.mode), 'c', pp.amount)$a$, $a$jsonb_build_object('a', public._m_key(pp.money_account_id, public._acct_paykey(pp.mode)), 'c', pp.amount)$a$]);

select public._m_patch('public._daybook_lines(integer[],integer[],date,date)'::regprocedure, array[
  $a$select e.location_id, e.entry_date, 'out', 'cash', 'expense', x.tot,$a$, $a$select e.location_id, e.entry_date, 'out', coalesce(public._m_mode(e.data ->> 'money_account_id'), 'cash') /* bos87 */, 'expense', x.tot,$a$,
  $a$x.n::text || ' line(s)', e.created_staff$a$, $a$x.n::text || ' line(s)' || coalesce(' · ' || public._m_name(public._m_id(e.data ->> 'money_account_id')), ''), e.created_staff$a$,
  $a$concat_ws(' · ', su.name, sp.wallet, sp.ref)$a$, $a$concat_ws(' · ', su.name, coalesce(public._m_name(sp.money_account_id), sp.wallet), sp.ref)$a$,
  $a$select * from public._d_daybook_rows(p_locs, p_from, p_to) /* bos85 */;$a$, $a$select * from public._d_daybook_rows(p_locs, p_from, p_to) /* bos85 */
  union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */;$a$]);

select public._m_patch('public._daybook_lines12(integer[],date,date)'::regprocedure, array[
  $a$concat_ws(' · ', c.name, r.wallet, r.ref)$a$, $a$concat_ws(' · ', c.name, coalesce(public._m_name(r.money_account_id), r.wallet), r.ref) /* bos87 */$a$,
  $a$concat_ws(' · ', su.name, f.wallet, f.ref)$a$, $a$concat_ws(' · ', su.name, coalesce(public._m_name(f.money_account_id), f.wallet), f.ref)$a$]);

select public._m_patch('public._daybook_lines23(integer[],date,date)'::regprocedure, array[
  $a$concat_ws(' · ', c.name, m.note)$a$, $a$concat_ws(' · ', c.name, public._m_name(m.money_account_id), m.note) /* bos87 */$a$,
  $a$concat_ws(' · ', e.employee_no, e.full_name_bn, p.note)$a$, $a$concat_ws(' · ', e.employee_no, e.full_name_bn, public._m_name(p.money_account_id), p.note)$a$,
  $a$concat_ws(' · ', e.employee_no, e.full_name_bn, a.note)$a$, $a$concat_ws(' · ', e.employee_no, e.full_name_bn, public._m_name(a.money_account_id), a.note)$a$,
  $a$concat_ws(' · ', q.paid_to, q.head, q.note)$a$, $a$concat_ws(' · ', q.paid_to, q.head, public._m_name(q.money_account_id), q.note)$a$]);

select public._m_patch('public.daybook_vs_journal(date,date,integer)'::regprocedure, array[
  $a$join public.acct_mappings a on a.account_id = jl.account_id and a.key in ('pay_cash', 'pay_bank', 'pay_card', 'pay_mobile')$a$,
  $a$join (select m0.account_id, m0.key from public.acct_mappings m0 union select ma.coa_account_id, 'pay_' || public._m_mode_of_kind(ma.kind) from public.money_accounts ma) a /* bos87 */
        on a.account_id = jl.account_id and a.key in ('pay_cash', 'pay_bank', 'pay_card', 'pay_mobile')$a$]);

select public._m_patch('public.acct_cash_flow(date,date,integer)'::regprocedure, array[
  $a$select array_agg(account_id) into ids from public.acct_mappings where key in ('pay_cash', 'pay_bank', 'pay_mobile');$a$,
  $a$select array_agg(account_id) into ids from (select account_id from public.acct_mappings where key in ('pay_cash', 'pay_bank', 'pay_mobile') union select coa_account_id from public.money_accounts) z; /* bos87 */$a$]);

select public._m_patch('public._e_balance_check(date,integer,integer)'::regprocedure, array[
  $a$eq jsonb; trial jsonb;$a$, $a$mnc jsonb; eq jsonb; trial jsonb;$a$,
  $a$red := not (eq ->> 'ok')::boolean or not (trial ->> 'ok')::boolean or jr_n > 0 or st_n > 0;$a$,
  $a$begin   -- bos87: money accounts total = the mapped ledger accounts (amber = a payment not posted yet, red = a ledger movement that belongs to no payment)
    mnc := public._m_balance_check(d);
    xc := xc || jsonb_build_object('money_accounts', mnc);
    if coalesce((mnc ->> 'amber')::boolean, false) then warn := warn || to_jsonb('money_accounts'::text); end if;
  exception when others then mnc := null; xc := xc || jsonb_build_object('money_accounts', jsonb_build_object('ran', false, 'skipped', sqlerrm));
  end;
  red := not (eq ->> 'ok')::boolean or not (trial ->> 'ok')::boolean or jr_n > 0 or st_n > 0 or coalesce((mnc ->> 'red')::boolean, false);$a$,
  $a$('journal', jr_n > 0), ('stock_identity', st_n > 0)) v(k, bad)$a$, $a$('journal', jr_n > 0), ('stock_identity', st_n > 0), ('money_accounts', coalesce((mnc ->> 'red')::boolean, false))) v(k, bad)$a$]);

select public._m_patch('public.opening_balance_post(jsonb,uuid,boolean,boolean)'::regprocedure, array[
  $a$if sec not in ('stock', 'cash', 'customer_dues', 'supplier_dues', 'capital', 'other') then$a$, $a$if sec not in ('stock', 'cash', 'customer_dues', 'supplier_dues', 'capital', 'other', 'money') then /* bos87 */$a$,
  $a$for x in select * from jsonb_array_elements(coalesce(p_json->'customer_dues', '[]')) loop$a$, $a$for x in select * from jsonb_array_elements(coalesce(p_json->'money', '[]')) loop   /* bos87: a registered money account, Dr its own chart account */
    ln := ln || public._m_opening_line(x);
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_json->'customer_dues', '[]')) loop$a$,
  $a$jid := (r->>'id')::bigint;$a$, $a$jid := (r->>'id')::bigint; perform public._m_opening_mark(p_json); /* bos87 */$a$]);

select public._m_patch('public.lock_check(date)'::regprocedure, array[
  $a$if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return; end if;$a$,
  $a$if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return; end if;
  if public._m_lock_exc(p_date) then return; end if;   -- bos87: an owner granted one-off exception (reason on record, shown in the Exceptions list)$a$]);

-- ============================================================================
-- PART G: approver choice. Not fixed: any role OR any named user, as a setting (named mode) and per individual entry, changeable at any time (audit_log line each time).
--   Kept from phase80/86: safe default stays mode self with nobody named; the decider is never the maker; the owner cannot hold the approver role he names;
--   owner_self_approve cannot be switched back on while the mode is named; the owner can always return to self (recovery).
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('owner_approver_users', 'lists', 'text', null, null, null, null, null,
  'নির্ধারিত অনুমোদনকারী ব্যক্তি (named হলে)', 'Named approver people (named mode)', 'Named approver people (used in named mode)',
  'এক বা একাধিক ব্যক্তি; ভূমিকার বদলে বা সঙ্গে', 'One or more people; instead of or together with the role', 17)
on conflict (key) do nothing;

create or replace function public._owner_approver_users() returns uuid[] language plpgsql stable security definer set search_path = public as $$
declare t text := public.rule_txt('owner_approver_users');
begin
  if t is null or t = '' then return '{}'; end if;
  return coalesce((select array_agg(x::uuid) from jsonb_array_elements_text(t::jsonb) x), '{}');
exception when others then return '{}';
end $$;

-- the setting itself may only change through the setter (keeps the legacy switch in step), like the two phase80 rules
create or replace function public._rules_mode_guard80() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if current_setting('role', true) = 'authenticated' and new.key in ('owner_approval_mode', 'owner_approver_role', 'owner_approver_users')
     and coalesce(new.value, new.default_value) is distinct from coalesce(old.value, old.default_value)
     and coalesce(current_setting('bos80.setting', true), '') <> '1' then raise exception 'use owner_approval_mode_set'; end if;
  return new;
end $$;

create or replace function public.owner_approval_mode() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('mode', public._owner_mode(), 'approver_role', public.rule_txt('owner_approver_role'), 'approver_users', to_jsonb(public._owner_approver_users()),
    'owner_self_approve', public.rule_on('owner_self_approve'));
end $$;

create or replace function public.owner_approval_mode_set2(p_mode text, p_role text default null, p_users uuid[] default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_m text := public._owner_mode(); old_r text := public.rule_txt('owner_approver_role'); old_u uuid[] := public._owner_approver_users();
  rl text := nullif(btrim(coalesce(p_role, '')), ''); us uuid[]; u uuid; clr boolean := btrim(coalesce(p_role, '')) = '-';
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_mode is null or p_mode not in ('self', 'named', 'logged', 'off') then raise exception 'bad_value'; end if;
  if clr then rl := null; end if;                                                         -- role '-' = no role, people only
  us := coalesce(p_users, old_u);                                                         -- null = keep, empty array = clear
  foreach u in array us loop
    if u = auth.uid() then raise exception 'owner_cannot_be_approver'; end if;
    if not exists (select 1 from public.profiles where id = u and status = 'active') then raise exception 'unknown_user'; end if;
  end loop;
  if p_mode = 'named' then
    if not clr then rl := coalesce(rl, old_r); end if;
    if rl is null and coalesce(array_length(us, 1), 0) = 0 then raise exception 'data_needed:owner_approver'; end if;
    if rl is not null then
      if not exists (select 1 from public.roles where code = rl and active) or rl = 'owner' then raise exception 'bad_role'; end if;
      if coalesce(array_length(us, 1), 0) = 0 and not exists (select 1 from public.user_roles ur join public.profiles p on p.id = ur.user_id where ur.role_code = rl and p.status = 'active' and p.id <> auth.uid()) then raise exception 'no_other_approver'; end if;
    end if;
  end if;
  if rl is not null and exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = rl) then raise exception 'owner_holds_approver_role'; end if;
  perform set_config('bos80.setting', '1', true);
  update public.rules set value = to_jsonb(p_mode), updated_at = now(), updated_by = auth.uid() where key = 'owner_approval_mode';
  if rl is not null then update public.rules set value = to_jsonb(rl), updated_at = now(), updated_by = auth.uid() where key = 'owner_approver_role';
  elsif clr then update public.rules set value = null, updated_at = now(), updated_by = auth.uid() where key = 'owner_approver_role'; end if;
  if p_users is not null then update public.rules set value = to_jsonb(to_jsonb(us)::text), updated_at = now(), updated_by = auth.uid() where key = 'owner_approver_users'; end if;
  perform public.set_rule('owner_self_approve', to_jsonb(p_mode <> 'named'));
  perform set_config('bos80.setting', '', true);
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'owner_approval_mode', 'rules', 'owner_approval_mode',
      jsonb_build_object('old', jsonb_build_object('mode', old_m, 'role', old_r, 'users', to_jsonb(old_u)), 'new', jsonb_build_object('mode', p_mode, 'role', case when clr then null else coalesce(rl, old_r) end, 'users', to_jsonb(us)), 'note', left(p_note, 300)));
  return jsonb_build_object('mode', p_mode, 'approver_role', case when clr then null else coalesce(rl, old_r) end, 'approver_users', to_jsonb(us), 'owner_self_approve', p_mode <> 'named');
end $$;

-- named mode guard, now with people and with the owner granted one-off approver exception. Decider <> maker always.
create or replace function public._owner_named_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare maker uuid; decider uuid; rl text; ok boolean; eid text;
begin
  if public._owner_mode() <> 'named' then return new; end if;
  if tg_table_name = 'entries' then
    if not (old.status = 'submitted' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.created_by; decider := new.checked_by; eid := new.id::text;
  else
    if not (old.status = 'pending' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.requested_by; decider := new.decided_by; eid := new.id::text;
  end if;
  if not exists (select 1 from public.user_roles where user_id = maker and role_code = 'owner') then return new; end if;
  rl := public.rule_txt('owner_approver_role');
  ok := decider is not null and decider <> maker /* bos86 */
        and ((rl is not null and exists (select 1 from public.user_roles where user_id = decider and role_code = rl)) or decider = any (public._owner_approver_users())) /* bos87 */;
  if not ok then
    if decider is not null and decider <> maker and public._m_grant_take('approver', 'owner_named', null, null, null, current_date, tg_table_name || ':' || eid) then return new; end if;
    raise exception 'named_approver_only';
  end if;
  return new;
end $$;

-- ---------- per individual entry ----------
create table if not exists public.entry_approvers (
  entry_id uuid primary key references public.entries(id),
  approver_user uuid, approver_role text,
  set_by uuid, set_at timestamptz not null default now(), reason text,
  check (approver_user is not null or approver_role is not null)
);
alter table public.entry_approvers enable row level security;
revoke all on public.entry_approvers from public, anon, authenticated;
drop trigger if exists entry_approvers_nodel on public.entry_approvers;
create trigger entry_approvers_nodel before delete on public.entry_approvers for each row execute function public.no_hard_delete();
drop trigger if exists audit_entry_approvers on public.entry_approvers;
create trigger audit_entry_approvers after insert or update on public.entry_approvers for each row execute function public.log_change('entry_id');
drop policy if exists entry_approvers_read on public.entry_approvers;
create policy entry_approvers_read on public.entry_approvers for select to authenticated using (public.is_owner() or approver_user = auth.uid()
  or exists (select 1 from public.entries e where e.id = entry_id and e.created_by = auth.uid()));
grant select on public.entry_approvers to authenticated;

create or replace function public._entry_approver_apply(p_entry uuid, p_user uuid, p_role text, p_reason text, p_by uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e public.entries; old_ public.entry_approvers;
begin
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'not found'; end if;
  if e.status in ('approved', 'rejected') then raise exception 'entry_decided'; end if;
  if p_user is null and nullif(btrim(coalesce(p_role, '')), '') is null then raise exception 'approver_required'; end if;
  if p_user is not null then
    if p_user = e.created_by then raise exception 'approver_is_maker'; end if;
    if not exists (select 1 from public.profiles where id = p_user and status = 'active') then raise exception 'unknown_user'; end if;
  end if;
  if nullif(btrim(coalesce(p_role, '')), '') is not null and not exists (select 1 from public.roles where code = btrim(p_role) and active) then raise exception 'bad_role'; end if;
  select * into old_ from public.entry_approvers where entry_id = p_entry;
  insert into public.entry_approvers (entry_id, approver_user, approver_role, set_by, set_at, reason) values (p_entry, p_user, nullif(btrim(coalesce(p_role, '')), ''), p_by, now(), left(p_reason, 300))
    on conflict (entry_id) do update set approver_user = excluded.approver_user, approver_role = excluded.approver_role, set_by = excluded.set_by, set_at = now(), reason = excluded.reason;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (p_by, (select staff_id from public.profiles where id = p_by), 'entry_approver_set', 'entries', p_entry::text,
      jsonb_build_object('old', case when old_.entry_id is not null then jsonb_build_object('user', old_.approver_user, 'role', old_.approver_role) end,
                         'new', jsonb_build_object('user', p_user, 'role', nullif(btrim(coalesce(p_role, '')), '')), 'reason', left(p_reason, 300)));
end $$;

create or replace function public.entry_approver_set(p_entry uuid, p_user uuid default null, p_role text default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries;
begin
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'not found'; end if;
  if not (public.is_owner() or e.created_by = auth.uid()) then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  perform public._entry_approver_apply(p_entry, p_user, p_role, p_reason, auth.uid());
  return jsonb_build_object('entry_id', p_entry, 'approver_user', p_user, 'approver_role', nullif(btrim(coalesce(p_role, '')), ''));
end $$;

-- choosing the approver at entry time: the form data may carry approver_user / approver_role
create or replace function public._entry_approver_sync() returns trigger language plpgsql security definer set search_path = public as $$
declare u uuid; r text; cur public.entry_approvers;
begin
  u := case when new.data ->> 'approver_user' ~ '^[0-9a-fA-F-]{36}$' then (new.data ->> 'approver_user')::uuid end;
  r := nullif(btrim(coalesce(new.data ->> 'approver_role', '')), '');
  if u is null and r is null then return null; end if;
  select * into cur from public.entry_approvers where entry_id = new.id;
  if found and cur.approver_user is not distinct from u and cur.approver_role is not distinct from r then return null; end if;
  perform public._entry_approver_apply(new.id, u, r, 'chosen at entry', coalesce(auth.uid(), new.created_by));
  return null;
end $$;
drop trigger if exists aa87_entry_approver_sync on public.entries;
create trigger aa87_entry_approver_sync after insert or update of data on public.entries for each row
  when (new.data ? 'approver_user' or new.data ? 'approver_role') execute function public._entry_approver_sync();

-- a designated approver (person or role) must be the one who decides that entry (never the maker); the owner can re-designate at any time or grant a one-off exception
create or replace function public._entry_approver_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare d public.entry_approvers; maker uuid; decider uuid; eid uuid; ok boolean;
begin
  if tg_table_name = 'entries' then
    if not (old.status = 'submitted' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.created_by; decider := new.checked_by; eid := new.id;
  else
    if not (old.status = 'pending' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.requested_by; decider := new.decided_by; eid := new.entry_id;
  end if;
  select * into d from public.entry_approvers where entry_id = eid;
  if not found then return new; end if;
  ok := decider is not null and decider <> maker and (decider = d.approver_user or (d.approver_role is not null and exists (select 1 from public.user_roles where user_id = decider and role_code = d.approver_role)));
  if not ok then
    if decider is not null and decider <> maker and public._m_grant_take('approver', 'entry_approver', null, null, null, current_date, 'entries:' || eid::text) then return new; end if;
    raise exception 'designated_approver_only';
  end if;
  return new;
end $$;
drop trigger if exists entries_approver_guard87 on public.entries;
create trigger entries_approver_guard87 before update on public.entries for each row execute function public._entry_approver_guard();
drop trigger if exists ecr_approver_guard87 on public.entry_change_requests;
create trigger ecr_approver_guard87 before update on public.entry_change_requests for each row execute function public._entry_approver_guard();

-- ============================================================================
-- PART H: privileges. Internals closed to browsers; the API checks its own permission.
-- ============================================================================
revoke all on function public._m_patch(regprocedure, text[]), public._p87_present(), public._m_id(text), public._m_key(bigint, text), public._m_mode_of_kind(text), public._m_mode(text), public._m_name(bigint),
  public._m_untag(text), public._m_linked_types(), public._m_voucher_total(jsonb), public._m_journal_bal(bigint, date), public._m_is_generic(bigint), public._m_accounting_ready(),
  public._m_src(bigint), public._m_reg(bigint), public._m_prove(bigint), public._m_grant_take(text, text, uuid, bigint, numeric, date, text), public._m_neg_check(bigint, numeric, text, uuid, date, text),
  public._m_event(text, jsonb), public._m_dir(text, jsonb), public._m_amount(text, jsonb), public._m_date(text, jsonb), public._m_src_bi(), public._m_src_bu(), public._m_entries_bi(),
  public._m_lock_exc(date), public._m_transfer_core(bigint, bigint, numeric, date, numeric, text, text, text, int, uuid, bigint), public._m_docs(date), public._m_daybook_rows(int[], date, date),
  public._m_csv(text), public._m_book(bigint, date), public._m_balance_check(date), public._m_opening_line(jsonb), public._m_opening_mark(jsonb),
  public._owner_approver_users(), public._rules_mode_guard80(), public._owner_named_guard(), public._entry_approver_apply(uuid, uuid, text, text, uuid), public._entry_approver_sync(), public._entry_approver_guard()
  from public, anon, authenticated;
revoke all on function public.money_account_add(text, text, text, text, text, text, int, text, numeric, date, text, text), public.money_account_update(bigint, text, text, text, text, text, text, int, text),
  public.money_account_set_active(bigint, boolean, text), public.money_accounts_list(date), public.money_pick(text, int), public.money_event_settings_list(),
  public.money_event_setting_set(text, bigint, boolean, boolean, boolean), public.money_exception_grant(text, text, uuid, uuid, text, bigint, numeric, date, int), public.money_exception_revoke(bigint, text),
  public.money_exceptions_list(text, int), public.money_exception_resolve(bigint, text), public.money_transfer_add(bigint, bigint, numeric, date, numeric, text, text, text, int, uuid),
  public.money_transfer_void(bigint, text), public.money_charge_add(bigint, text, numeric, date, text, text, int, uuid), public.money_charge_void(bigint, text),
  public.money_recurring_add(text, bigint, bigint, numeric, int, date, date, numeric, text, int), public.money_recurring_set_active(bigint, boolean), public.money_recurring_list(), public.money_recurring_run(date),
  public.money_statement(bigint, date, date, int, int), public.money_statement_csv(bigint, date, date, int), public.money_summary(date, date, int), public.money_check_save(bigint, date, numeric, uuid),
  public.money_check_explain(bigint, text), public.money_checks_list(bigint, int), public.money_statements(date, date, int), public.money_salary_sources(date, date, int), public.money_opening_json(),
  public.owner_approval_mode(), public.owner_approval_mode_set2(text, text, uuid[], text), public.entry_approver_set(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.money_account_add(text, text, text, text, text, text, int, text, numeric, date, text, text), public.money_account_update(bigint, text, text, text, text, text, text, int, text),
  public.money_account_set_active(bigint, boolean, text), public.money_accounts_list(date), public.money_pick(text, int), public.money_event_settings_list(),
  public.money_event_setting_set(text, bigint, boolean, boolean, boolean), public.money_exception_grant(text, text, uuid, uuid, text, bigint, numeric, date, int), public.money_exception_revoke(bigint, text),
  public.money_exceptions_list(text, int), public.money_exception_resolve(bigint, text), public.money_transfer_add(bigint, bigint, numeric, date, numeric, text, text, text, int, uuid),
  public.money_transfer_void(bigint, text), public.money_charge_add(bigint, text, numeric, date, text, text, int, uuid), public.money_charge_void(bigint, text),
  public.money_recurring_add(text, bigint, bigint, numeric, int, date, date, numeric, text, int), public.money_recurring_set_active(bigint, boolean), public.money_recurring_list(), public.money_recurring_run(date),
  public.money_statement(bigint, date, date, int, int), public.money_statement_csv(bigint, date, date, int), public.money_summary(date, date, int), public.money_check_save(bigint, date, numeric, uuid),
  public.money_check_explain(bigint, text), public.money_checks_list(bigint, int), public.money_statements(date, date, int), public.money_salary_sources(date, date, int), public.money_opening_json(),
  public.owner_approval_mode(), public.owner_approval_mode_set2(text, text, uuid[], text), public.entry_approver_set(uuid, uuid, text, text) to authenticated;
