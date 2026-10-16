-- Phase 82 (bos82, builder C) - G1 + G12 + G8: salary accrual, Monthly Close, partner profit share posting.
-- Additive and paste-twice safe (create or replace / if not exists / on conflict do nothing). Paste AFTER phase79 (and after phase80/81 if they exist).
--
-- WHAT THIS DOES
--   G1  Salary is a MONTHLY ACCRUAL, not a daily expense. When the owner turns the rule payroll_accrual_on ON (default OFF) and gives the first month
--       (payroll_accrual_from), an approved payroll run posts ONE entry per place on the month end:  Dr 5200 salary expense (net pay + advance recovery),
--       Cr 2200 accrued salaries (net pay), Cr 1220 staff advances (advance recovery).  A salary payment then posts  Dr 2200, Cr cash / bKash / bank.
--       Runs of earlier months, and runs that already have a payment posted the old way, stay on today's cash-basis posting (the choice is sticky per run).
--   G12 Salary is not a daily cost. biz_daily (verified in phase72) holds sales and COGS only, so the day sheet never carried salary. c_daily_profit() gives a
--       day profit that leaves salary out (rule salary_in_daily_off, default ON); c_month_close_preview() carries the salary as the monthly cost.
--       Where the salary is PAID FROM is the rule salary_pay_source: by_payment (default, what the payer chose) | cash | mobile (bKash) | bank.
--   G8  Partner profit share posting: an approved partner settlement posts Dr 3400 partner profit share (appropriation), Cr 2600 partner profit payable;
--       a settlement payment posts Dr 2600, Cr cash / bank / wallet. Rule partner_settlement_post_on (default OFF), rule partner_accrue_at:
--       approval (default: liability is booked when approved) | payment (nothing is booked until the money is paid: Dr 3400, Cr cash).
--       c_partner_month_split() is the monthly profit split by the share % written in the agreements (read only, never invents a percent).
--   Monthly Close: c_month_close_preview / c_month_close / c_month_reopen / c_month_closes (append-only log, blockers, snapshot).
--
-- HOW THIS FILE STAYS OUT OF THE SHARED FUNCTIONS
--   Nothing existing is edited. The journal sources are produced by _c_docs(p_start), which returns exactly the columns of _acct_docs. Until the integrator adds the
--   one-line hooks in docs/integration/C.md, c_post_pending() (own poster, same _acct_write) posts the partner sources only; the payroll accrual stays dormant
--   (the hook guard _c_hooks_ok() keeps the basis on cash) so a half-integrated database can never count a salary twice.
--
-- Needs: phase40 (journal), phase42 (payroll), phase44 (partners), phase52 (shadow engine, salary_exp / staff_advance mappings), phase79 (_acct_docs).

do $g$ begin
  if to_regprocedure('public._acct_docs(date)') is null or to_regprocedure('public._acct_sid52(text, text)') is null
     or to_regprocedure('public.payroll_approve(bigint)') is null or to_regprocedure('public.partner_settlement_approve(bigint)') is null then
    raise exception 'phase82 needs phases 40, 42, 44, 52 and 79 pasted first';
  end if;
end $g$;

-- ---------- 1. rules (owner decisions, safe defaults) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('payroll_accrual_on', 'people', 'switch', 'false', null, null, null, null,
  'বেতন মাসের খরচ হিসেবে জমা (accrual)', 'বেতন monthly accrual হিসেবে হিসাবে ওঠে', 'Book salary as a monthly accrual',
  'বন্ধ থাকলে আগের মতোই: বেতন দেওয়ার দিনে খরচ। চালু হলে অনুমোদিত বেতন শিট মাসের শেষে খরচ ও বকেয়া বেতন হিসেবে ওঠে, পরে টাকা দিলে বকেয়া কমে। শুরুর মাস নিচের সেটিংয়ে দিতে হবে।',
  'Off = as before: salary is a cost on the day it is paid. On = an approved payroll run is booked at month end as a cost and as accrued salary; paying it later clears the accrual. Give the first month below.', 830),
 ('payroll_accrual_from', 'people', 'text', null, null, null, null, null,
  'কোন মাস থেকে বেতন accrual (তারিখ YYYY-MM-01)', 'Accrual শুরুর মাস (YYYY-MM-01)', 'First month of salary accrual (YYYY-MM-01)',
  'ফাঁকা থাকলে accrual চালু থাকলেও কিছু উঠবে না। আগের মাসগুলো আগের নিয়মেই থাকে।', 'Blank = nothing is accrued even if the switch is on. Earlier months keep the old posting.', 831),
 ('salary_pay_source', 'people', 'choice', '"by_payment"', null, '["by_payment","cash","mobile","bank"]', null, null,
  'বেতন কোথা থেকে দেওয়া হয়: by_payment = যে মাধ্যমে দেওয়া হলো, cash = নগদ, mobile = বিকাশ/ওয়ালেট, bank = ব্যাংক',
  'Salary কোথা থেকে দেওয়া হয়', 'Salary is paid from',
  'by_payment হলে বেতন দেওয়ার সময় বাছা মাধ্যম হিসাবে যাবে। অন্যটি বাছলে সব বেতন সেই হিসাব থেকে বের হবে। এখনও যা পোস্ট হয়নি শুধু তার ওপর খাটবে।',
  'by_payment = the mode picked when paying. The others send every salary payment to that account. Only affects entries not yet posted.', 832),
 ('salary_in_daily_off', 'people', 'switch', 'true', null, null, null, null,
  'দৈনিক লাভে বেতন ধরা হবে না (মাসিক ক্লোজে ধরা হয়)', 'Daily profit-এ salary ধরা হবে না', 'Keep salary out of the daily profit (Monthly Close carries it)',
  'চালু (ডিফল্ট) = দৈনিক লাভে বেতন নেই, মাসের হিসাবে আছে। বন্ধ = দৈনিক লাভের রিপোর্টে মাসের বেতন দিনে ভাগ না করে আলাদা লাইনে দেখায়।',
  'On (default) = daily profit leaves salary out; the month carries it. Off = the daily profit report shows the month salary as a separate line.', 833),
 ('partner_settlement_post_on', 'books', 'switch', 'false', null, null, null, null,
  'অংশীদারের মুনাফার ভাগ খতিয়ানে ওঠে', 'Partner profit share journal-এ উঠবে', 'Post partner profit shares to the books',
  'বন্ধ = এখনকার মতো কিছু উঠে না। চালু হলে অনুমোদিত সেটেলমেন্ট ও তার পেমেন্ট খতিয়ানে ওঠে।',
  'Off = nothing is posted, as today. On = an approved settlement and its payments are posted to the books.', 840),
 ('partner_accrue_at', 'books', 'choice', '"approval"', null, '["approval","payment"]', null, null,
  'অংশীদারের মুনাফা কখন খতিয়ানে: approval = অনুমোদনের দিন (দেনা), payment = টাকা দেওয়ার দিন',
  'Partner profit কখন book হবে: approval | payment', 'Book the partner profit at: approval | payment',
  'মালিক ঠিক করবেন কখন দেওয়া হবে। approval হলে অনুমোদনেই দেনা ওঠে; payment হলে টাকা দিলে তবেই ওঠে। একটি সেটেলমেন্ট একবার উঠলে তার নিয়ম বদলায় না।',
  'The owner decides when the profit is paid. approval = the debt is booked when approved; payment = booked only when paid. A settlement keeps the basis it was first posted with.', 841)
 on conflict (key) do nothing;

-- ---------- 2. chart + mappings ----------
do $seed$
declare c1 text; c2 text;
begin
  if not exists (select 1 from public.coa_accounts where is_system and name_en = 'Partner profit payable') then
    c1 := case when exists (select 1 from public.coa_accounts where code = '2600') then '2610' else '2600' end;
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort, parent_id)
      select c1, 'অংশীদারের মুনাফা দেনা', 'Partner profit payable', 'liability', 'credit', false, true, 106, (select id from public.coa_accounts where code = '2000')
       where not exists (select 1 from public.coa_accounts where code = c1);
  end if;
  if not exists (select 1 from public.coa_accounts where is_system and name_en = 'Partner profit share (appropriation)') then
    c2 := case when exists (select 1 from public.coa_accounts where code = '3400') then '3410' else '3400' end;
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort, parent_id)
      select c2, 'অংশীদারের মুনাফার ভাগ (বণ্টন, বিয়োগ)', 'Partner profit share (appropriation)', 'equity', 'debit', false, true, 204, (select id from public.coa_accounts where code = '3000')
       where not exists (select 1 from public.coa_accounts where code = c2);
  end if;
end $seed$;

insert into public.acct_mappings (key, account_id, label_bn, label_en)
select v.k, a.id, v.lb, v.le from (values
  ('salary_accrued', '2200', 'বকেয়া বেতন (মাসের accrual)', 'Accrued salaries (monthly accrual)')
) as v(k, c, lb, le) join public.coa_accounts a on a.code = v.c
on conflict (key) do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'partner_payable', a.id, 'অংশীদারের মুনাফা দেনা', 'Partner profit payable'
  from public.coa_accounts a where a.is_system and a.name_en = 'Partner profit payable' order by a.code limit 1
on conflict (key) do nothing;
-- one mapping per settlement line kind, all pointing at the appropriation account by default; the owner may re-point royalty / fee to an expense account
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'partner_ps_' || k.kind, a.id, 'অংশীদার সেটেলমেন্ট: ' || k.kind, 'Partner settlement: ' || k.kind
  from (values ('share'), ('royalty'), ('fee'), ('return'), ('payback'), ('guarantee')) k(kind)
  cross join lateral (select x.id from public.coa_accounts x where x.is_system and x.name_en = 'Partner profit share (appropriation)' order by x.code limit 1) a
on conflict (key) do nothing;

-- ---------- 3. tables ----------
-- Monthly Close trail: append-only. The state of a month is its newest row (close or reopen).
create table if not exists public.c_month_close_log (
  id bigserial primary key,
  month date not null check (extract(day from month) = 1),
  action text not null check (action in ('close', 'reopen')),
  snapshot jsonb,
  note text check (note is null or length(note) <= 500),
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create index if not exists c_month_close_log_m on public.c_month_close_log (month, id);

create or replace function public._c_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: the month close trail cannot be changed or deleted'; end $$;
drop trigger if exists c_month_close_log_ro on public.c_month_close_log;
create trigger c_month_close_log_ro before update or delete on public.c_month_close_log for each row execute function public._c_ro();
drop trigger if exists c_month_close_log_ro_t on public.c_month_close_log;
create trigger c_month_close_log_ro_t before truncate on public.c_month_close_log for each statement execute function public._c_ro();
drop trigger if exists audit_c_month_close_log on public.c_month_close_log;
create trigger audit_c_month_close_log after insert on public.c_month_close_log for each row execute function public.log_change('id');

alter table public.c_month_close_log enable row level security;
revoke all on public.c_month_close_log from public, anon, authenticated;
grant select on public.c_month_close_log to authenticated;
drop policy if exists c_month_close_log_sel on public.c_month_close_log;
create policy c_month_close_log_sel on public.c_month_close_log for select to authenticated using (public._acct_manage());

-- ---------- 4. small helpers ----------
create or replace function public._c_me(p_m date) returns date language sql immutable as $$ select (date_trunc('month', p_m) + interval '1 month' - interval '1 day')::date $$;

create or replace function public._c_accrual_from() returns date language plpgsql stable security definer set search_path = public as $$
declare t text := public.rule_txt('payroll_accrual_from');
begin
  if t is null or t !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return null; end if;
  return date_trunc('month', t::date)::date;
exception when others then return null;
end $$;

-- are the one-line hooks of docs/integration/C.md installed in _acct_docs? Without them the accrual must stay dormant (no double count).
create or replace function public._c_hooks_ok() returns boolean language sql stable security definer set search_path = public as $$
  select position('_c_docs' in d) > 0 and position('_c_run_skip' in d) > 0
    from (select pg_get_functiondef('public._acct_docs(date)'::regprocedure) d) z
$$;

-- 'accrual' or 'cash' for one payroll run. Sticky: once an accrual (or an accrual-style payment) is posted the run stays accrual; once a cash-style payment is posted it stays cash.
create or replace function public._c_run_basis(p_run bigint) returns text language plpgsql stable security definer set search_path = public as $$
declare r public.payroll_runs; f date;
begin
  select * into r from public.payroll_runs where id = p_run;
  if not found then return 'cash'; end if;
  if exists (select 1 from public.journal_entries e where e.source_type = 'payroll_accrual' and e.reverses_id is null and e.source_id like p_run::text || ':%') then return 'accrual'; end if;
  if exists (select 1 from public.journal_entries e join public.payroll_payments p on p.run_id = p_run and e.source_type = 'payroll_pay_accr' and e.source_id = p.id::text and e.reverses_id is null) then return 'accrual'; end if;
  if exists (select 1 from public.journal_entries e join public.payroll_payments p on p.run_id = p_run and e.source_type = 'payroll_payment'
              and (e.source_id = p.id::text or e.source_id like p.id::text || ':g%') and e.reverses_id is null) then return 'cash'; end if;
  f := public._c_accrual_from();
  if public.rule_on('payroll_accrual_on') and f is not null and r.month >= f and public._c_hooks_ok() then return 'accrual'; end if;
  return 'cash';
end $$;

create or replace function public._c_accrual_covers(p_run bigint) returns boolean language sql stable security definer set search_path = public as $$
  select public._c_run_basis(p_run) = 'accrual' $$;

-- HOOK 1: replaces  public.is_shadow('payroll_runs', p.run_id::text)  in the payroll_payment block of _acct_docs
create or replace function public._c_run_skip(p_run bigint) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_shadow('payroll_runs', p_run::text) or public._c_run_basis(p_run) = 'accrual' $$;

-- HOOK 2: replaces  public._acct_paykey(p.mode)  on the credit line of the payroll_payment block. The account the salary leaves from.
create or replace function public._c_salary_paykey(p_mode text) returns text language sql stable security definer set search_path = public as $$
  select public._acct_paykey(case coalesce(public.rule_txt('salary_pay_source'), 'by_payment') when 'cash' then 'cash' when 'mobile' then 'mobile' when 'bank' then 'bank' else p_mode end) $$;

-- the payment mode the screen should pre-select when salary is paid (null = the payer chooses)
create or replace function public.c_salary_pay_default() returns text language sql stable security definer set search_path = public as $$
  select case coalesce(public.rule_txt('salary_pay_source'), 'by_payment') when 'by_payment' then null else public.rule_txt('salary_pay_source') end $$;

-- 'accrual' (booked when approved) or 'payment' (booked when paid) for one partner settlement. Sticky once something is posted.
create or replace function public._c_settle_basis(p_s bigint) returns text language plpgsql stable security definer set search_path = public as $$
declare pa bigint;
begin
  if exists (select 1 from public.journal_entries e where e.source_type = 'partner_settle' and e.source_id = p_s::text and e.reverses_id is null) then return 'accrual'; end if;
  select account_id into pa from public.acct_mappings where key = 'partner_payable';
  if exists (select 1 from public.journal_entries e join public.partner_settlement_payments pp on e.source_type = 'partner_settle_pay' and e.source_id = pp.id::text and e.reverses_id is null
              join public.partner_settlement_lines l on l.id = pp.line_id and l.settlement_id = p_s
             where exists (select 1 from public.journal_lines jl where jl.entry_id = e.id and jl.account_id = pa)) then return 'accrual'; end if;
  if exists (select 1 from public.journal_entries e join public.partner_settlement_payments pp on e.source_type = 'partner_settle_pay' and e.source_id = pp.id::text and e.reverses_id is null
              join public.partner_settlement_lines l on l.id = pp.line_id and l.settlement_id = p_s) then return 'payment'; end if;
  return case coalesce(public.rule_txt('partner_accrue_at'), 'approval') when 'payment' then 'payment' else 'accrual' end;
end $$;

-- exact split of a total over percentages, to the paisa, largest remainder first: the parts always add up to the total
create or replace function public._c_split(p_total numeric, p_pcts numeric[]) returns numeric[] language plpgsql immutable as $$
declare n int := coalesce(array_length(p_pcts, 1), 0); cents numeric := round(p_total * 100); base numeric[] := '{}'; rem numeric[] := '{}'; i int; left_ numeric; tot numeric := 0; idx int; best numeric; res numeric[] := '{}';
begin
  if n = 0 then return '{}'; end if;
  if p_total < 0 then raise exception 'negative_total'; end if;
  for i in 1..n loop
    if p_pcts[i] is null or p_pcts[i] < 0 then raise exception 'bad_share'; end if;
    tot := tot + p_pcts[i];
  end loop;
  if abs(tot - 100) > 0.0001 then raise exception 'shares_not_100'; end if;
  left_ := cents;
  for i in 1..n loop
    base[i] := floor(cents * p_pcts[i] / 100); rem[i] := cents * p_pcts[i] / 100 - base[i]; left_ := left_ - base[i];
  end loop;
  while left_ > 0 loop
    idx := 1; best := rem[1];
    for i in 2..n loop if rem[i] > best then idx := i; best := rem[i]; end if; end loop;
    base[idx] := base[idx] + 1; rem[idx] := -1; left_ := left_ - 1;
  end loop;
  for i in 1..n loop res[i] := base[i] / 100; end loop;
  return res;
end $$;

-- the lines of one salary accrual entry (one run, one place)
create or replace function public._c_accrual_lines(p_run bigint, p_loc int) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(j order by o, e), '[]'::jsonb) from (
    select 1 o, l.employee_id::text e, jsonb_build_object('a', 'salary_exp', 'd', l.net + l.advance_recovery, 'pt', 'staff', 'pid', l.employee_id::text) j
      from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id
     where l.run_id = p_run and l.active and coalesce(l.location_id, r.location_id, 0) = coalesce(p_loc, 0) and l.net + l.advance_recovery > 0
    union all
    select 2, l.employee_id::text, jsonb_build_object('a', 'salary_accrued', 'c', l.net, 'pt', 'staff', 'pid', l.employee_id::text)
      from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id
     where l.run_id = p_run and l.active and coalesce(l.location_id, r.location_id, 0) = coalesce(p_loc, 0) and l.net > 0
    union all
    select 3, l.employee_id::text, jsonb_build_object('a', 'staff_advance', 'c', l.advance_recovery, 'pt', 'staff', 'pid', l.employee_id::text)
      from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id
     where l.run_id = p_run and l.active and coalesce(l.location_id, r.location_id, 0) = coalesce(p_loc, 0) and l.advance_recovery > 0
  ) y $$;

-- ---------- 5. the journal sources (same columns as _acct_docs) ----------
create or replace function public._c_docs(p_start date) returns table(
  source_type text, source_id text, entry_date date, location_id int, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
language plpgsql stable security definer set search_path = public as $fn$
declare p_on boolean := public.rule_on('partner_settlement_post_on');
begin
  -- 1. salary accrual: one entry per (run, place), dated the month end (not later than today). Only runs whose basis is accrual.
  return query
  select 'payroll_accrual'::text, g.sid, g.d, nullif(g.loc, 0), ('Salary accrued ' || to_char(g.month, 'YYYY-MM') || ' PR-' || g.run_id::text)::text, null::text,
         g.status in ('approved', 'paid') and not g.shadow, (g.void_at at time zone 'Asia/Dhaka')::date, null::text,
         case when g.status in ('approved', 'paid') and not g.shadow and g.bad then 'advance_recovery_exceeds_balance' end,
         case when g.status in ('approved', 'paid') and not g.shadow and not g.bad then public._c_accrual_lines(g.run_id, g.loc) end
  from (
    select r.id run_id, r.month, r.status, r.void_at, coalesce(l.location_id, r.location_id, 0) loc,
           r.id::text || ':' || coalesce(l.location_id, r.location_id, 0)::text sid,
           least(public._c_me(r.month), public._acct_today()) d,
           public.is_shadow('payroll_runs', r.id::text) shadow,
           bool_or(l.advance_recovery > coalesce((select sum(x.amount) from public.employee_advance_recoveries x where x.line_id = l.id and x.status = 'active'), 0) + 0.004 and r.status <> 'void') bad
      from public.payroll_runs r join public.payroll_lines l on l.run_id = r.id
     where public._c_run_basis(r.id) = 'accrual'
     group by r.id, r.month, r.status, r.void_at, coalesce(l.location_id, r.location_id, 0)) g
  where g.d >= p_start
    and public._acct_need('payroll_accrual', g.sid, g.status in ('approved', 'paid') and not g.shadow);

  -- 2. salary payments of an accrual run: Dr accrued salaries, Cr cash / bKash / bank (rule salary_pay_source)
  return query
  select 'payroll_pay_accr'::text, p.id::text, p.pay_date, p.location_id, ('Salary payment PR-' || p.run_id::text)::text, null::text,
         p.status = 'done', (p.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
         case when p.status = 'done' then jsonb_build_array(
           jsonb_build_object('a', 'salary_accrued', 'd', p.amount, 'pt', 'staff', 'pid', p.employee_id::text),
           jsonb_build_object('a', public._c_salary_paykey(p.mode), 'c', p.amount)) end
  from public.payroll_payments p
  where p.pay_date >= p_start and public._c_run_basis(p.run_id) = 'accrual' and not public.is_shadow('payroll_runs', p.run_id::text)
    and public._acct_need('payroll_pay_accr', p.id::text, p.status = 'done');

  -- 3. partner settlement approved: Dr profit share (appropriation), Cr partner profit payable. Funded-outside lines never touch the business books.
  return query
  select 'partner_settle'::text, s.id::text, (s.approved_at at time zone 'Asia/Dhaka')::date, v.location_id, ('Partner profit share PS-' || s.id::text)::text, null::text,
         s.status in ('approved', 'paid'), (s.void_at at time zone 'Asia/Dhaka')::date, null::text,
         case when s.status in ('approved', 'paid') and not exists (select 1 from public.partner_settlement_lines l where l.settlement_id = s.id and not l.funded_outside) then 'all_funded_outside' end,
         case when s.status in ('approved', 'paid') then (
           select jsonb_agg(j order by o, k) from (
             select 1 o, l.id k, jsonb_build_object('a', 'partner_ps_' || l.kind, 'd', l.amount, 'pt', 'partner', 'pid', l.party_id::text) j
               from public.partner_settlement_lines l where l.settlement_id = s.id and not l.funded_outside
             union all
             select 2, l.id, jsonb_build_object('a', 'partner_payable', 'c', l.amount, 'pt', 'partner', 'pid', l.party_id::text)
               from public.partner_settlement_lines l where l.settlement_id = s.id and not l.funded_outside) y) end
  from public.partner_settlements s
  join public.partner_agreements a on a.id = s.agreement_id join public.partner_ventures v on v.id = a.venture_id
  where s.approved_at is not null and (s.approved_at at time zone 'Asia/Dhaka')::date >= p_start
    and (p_on or exists (select 1 from public.journal_entries e where e.source_type = 'partner_settle' and e.source_id = s.id::text and e.reverses_id is null))
    and public._c_settle_basis(s.id) = 'accrual'
    and public._acct_need('partner_settle', s.id::text, s.status in ('approved', 'paid'));

  -- 4. partner settlement payments: Dr payable (accrual basis) or Dr profit share (payment basis), Cr cash / bank / wallet
  return query
  select 'partner_settle_pay'::text, pp.id::text, pp.paid_on, v.location_id, ('Partner payment PS-' || s.id::text)::text, null::text,
         s.status <> 'void', null::date, null::text, null::text,
         jsonb_build_array(
           jsonb_build_object('a', case when public._c_settle_basis(s.id) = 'accrual' then 'partner_payable' else 'partner_ps_' || l.kind end, 'd', pp.amount, 'pt', 'partner', 'pid', l.party_id::text),
           jsonb_build_object('a', public._acct_paykey(pp.mode), 'c', pp.amount))
  from public.partner_settlement_payments pp
  join public.partner_settlement_lines l on l.id = pp.line_id and not l.funded_outside
  join public.partner_settlements s on s.id = l.settlement_id
  join public.partner_agreements a on a.id = s.agreement_id join public.partner_ventures v on v.id = a.venture_id
  where pp.paid_on >= p_start
    and (p_on or exists (select 1 from public.journal_entries e where e.source_type = 'partner_settle_pay' and e.source_id = pp.id::text and e.reverses_id is null))
    and public._acct_need('partner_settle_pay', pp.id::text, s.status <> 'void');
end $fn$;
revoke all on function public._c_docs(date) from public, anon, authenticated;

-- ---------- 6. own poster (same engine as acct_post_pending, only for the sources above) ----------
create or replace function public.c_post_pending(p_dry boolean default false, p_limit int default 500) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st date := public._acct_start(); d record; n int := 0; posted int := 0; rev int := 0; locked int := 0; ln jsonb; orig public.journal_entries; rdate date;
        by_type jsonb := '{}'; waiting jsonb := '{}'; errors jsonb := '[]'; prev jsonb := '[]'; tot_d numeric := 0; tot_c numeric := 0; lim int := least(greatest(coalesce(p_limit, 500), 1), 3000);
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true, 'dry', p_dry); end if;
  if not p_dry and not public.rule_on('accounting_on') then raise exception 'accounting_off'; end if;
  if not p_dry then perform pg_advisory_xact_lock(hashtextextended('acct_post', 0)); end if;
  for d in select * from public._c_docs(st) order by 3, 1, 2 loop
    if d.waiting is not null then waiting := jsonb_set(waiting, array[d.waiting], to_jsonb(coalesce((waiting->>d.waiting)::int, 0) + 1)); continue; end if;
    if n >= lim then exit; end if;
    begin
      if d.live then
        if public._acct_locked(d.entry_date) then locked := locked + 1; continue; end if;
        ln := public._acct_resolve(public._acct_merge(d.lines), d.location_id);
        select coalesce(sum((x->>'debit')::numeric), 0), coalesce(sum((x->>'credit')::numeric), 0) into tot_d, tot_c from jsonb_array_elements(ln) x;
        if tot_d <> tot_c or tot_d <= 0 then raise exception 'unbalanced: debit % credit %', tot_d, tot_c; end if;
        if p_dry then
          if jsonb_array_length(prev) < 40 then prev := prev || jsonb_build_object('date', d.entry_date, 'source_type', d.source_type, 'source_id', d.source_id, 'memo', d.memo, 'debit', tot_d, 'credit', tot_c); end if;
        else
          perform public._acct_write(d.entry_date, d.location_id, d.source_type, d.source_id, d.subtype, d.memo, d.flags, ln);
        end if;
        posted := posted + 1;
        by_type := jsonb_set(by_type, array[d.source_type], to_jsonb(coalesce((by_type->>d.source_type)::int, 0) + 1));
      else
        select * into orig from public.journal_entries o where o.source_type = d.source_type and o.source_id = d.source_id and o.reverses_id is null;
        rdate := greatest(coalesce(d.void_date, public._acct_today()), orig.entry_date);
        if public._acct_locked(rdate) then locked := locked + 1; continue; end if;
        if not p_dry then perform public._acct_reverse(orig.id, rdate, 'Reversal: ' || orig.memo); end if;
        rev := rev + 1;
        by_type := jsonb_set(by_type, array[d.source_type || '_reversed'], to_jsonb(coalesce((by_type->>(d.source_type || '_reversed'))::int, 0) + 1));
      end if;
      n := n + 1;
    exception when others then
      errors := errors || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'error', sqlerrm);
      n := n + 1;
    end;
  end loop;
  return jsonb_build_object('dry', p_dry, 'start', st, 'posted', posted, 'reversed', rev, 'by_type', by_type, 'locked', locked, 'waiting', waiting, 'errors', errors,
    'hooks_installed', public._c_hooks_ok(), 'preview', case when p_dry then prev end);
end $$;

-- ---------- 7. read helpers for the P&L / screens ----------
-- HOOK 3 (P&L): salary expense of the app payroll by month and place (accrual: net pay + advance recovery of an approved or paid run; shadow runs are the form's)
create or replace function public.c_salary_by_month(d1 date, d2 date, locs int[]) returns table(m date, loc int, amt numeric)
language sql stable security definer set search_path = public as $$
  select r.month, coalesce(l.location_id, r.location_id), round(sum(l.net + l.advance_recovery), 2)
    from public.payroll_runs r join public.payroll_lines l on l.run_id = r.id and l.active
   where r.status in ('approved', 'paid') and not public.is_shadow('payroll_runs', r.id::text)
     and r.month between date_trunc('month', d1)::date and d2 and coalesce(l.location_id, r.location_id) = any (locs)
   group by 1, 2 $$;
revoke all on function public.c_salary_by_month(date, date, int[]) from public, anon, authenticated;

-- day profit with salary left out (rule salary_in_daily_off). Sales are net of discounts as biz_daily gives them; expenses are the approved 10-2 vouchers and quick expenses.
create or replace function public.c_daily_profit(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; sal_off boolean := coalesce(public.rule_on('salary_in_daily_off'), true); sal numeric := 0;
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('day', b.sale_date, 'location_id', b.location_id, 'revenue', b.revenue, 'cogs', b.cogs, 'costed_revenue', b.costed_rev,
           'profit_before_expenses', case when b.cogs is null then null else round(b.revenue - b.cogs, 2) end) order by b.sale_date, b.location_id), '[]'::jsonb)
    into rows from public.biz_daily(p_from, p_to, p_loc) b;
  if not sal_off and (public.is_owner() or public.has_grant('salary_view')) then
    select coalesce(sum(s.amt), 0) into sal from public.c_salary_by_month(p_from, p_to, (select coalesce(array_agg(l.id), '{}') from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id))) s;
  end if;
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc, 'days', rows, 'salary_included_in_days', false,
    'salary_in_daily_off', sal_off, 'month_salary_line', case when sal_off then null else sal end,
    'note', 'Salary is a monthly cost. See Monthly Close for the month salary and the month profit.');
end $$;

-- ---------- 8. Monthly Close ----------
create or replace function public._c_close_state(p_m date) returns text language sql stable security definer set search_path = public as $$
  select coalesce((select case when action = 'close' then 'closed' else 'open' end from public.c_month_close_log where month = p_m order by id desc limit 1), 'open') $$;

create or replace function public.c_month_close_preview(p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date; me date := public._c_me(p_month); st date := public._acct_start(); runs jsonb; blockers jsonb := '[]'; warns jsonb := '[]';
        pl jsonb; sal_j numeric := 0; sid bigint; unposted int := 0; waiting int := 0; unb bigint; adv_out numeric; nrun int; ndraft int; v_pend jsonb;
        sal_exp numeric := 0; sal_paid numeric := 0; sal_net numeric := 0; hooks boolean := public._c_hooks_ok();
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_month is null then raise exception 'bad_month'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('run_id', r.id, 'location_id', r.location_id, 'status', r.status, 'shadow', public.is_shadow('payroll_runs', r.id::text),
           'basis', case when public.is_shadow('payroll_runs', r.id::text) then 'form' else public._c_run_basis(r.id) end, 'staff', x.n, 'net', x.net, 'advance_recovery', x.rec, 'salary_expense', x.net + x.rec, 'paid', x.paid, 'unpaid', x.net - x.paid,
           'accrual_posted', exists (select 1 from public.journal_entries e where e.source_type = 'payroll_accrual' and e.reverses_id is null and e.source_id like r.id::text || ':%')) order by r.id), '[]'::jsonb),
         count(*), count(*) filter (where r.status = 'draft'),
         coalesce(sum(x.net + x.rec) filter (where r.status in ('approved', 'paid') and not public.is_shadow('payroll_runs', r.id::text)), 0),
         coalesce(sum(x.paid) filter (where r.status in ('approved', 'paid') and not public.is_shadow('payroll_runs', r.id::text)), 0),
         coalesce(sum(x.net) filter (where r.status in ('approved', 'paid') and not public.is_shadow('payroll_runs', r.id::text)), 0)
    into runs, nrun, ndraft, sal_exp, sal_paid, sal_net
    from public.payroll_runs r
    cross join lateral (select count(*) n, coalesce(sum(l.net), 0) net, coalesce(sum(l.advance_recovery), 0) rec, coalesce(sum(l.paid_amount), 0) paid
                          from public.payroll_lines l where l.run_id = r.id and l.active) x
   where r.month = m and r.status <> 'void';
  if st is null then blockers := blockers || to_jsonb('accounting_start_missing'::text); end if;
  if me > public._acct_today() then blockers := blockers || to_jsonb('month_not_finished'::text); end if;
  if ndraft > 0 then blockers := blockers || to_jsonb('payroll_run_not_approved'::text); end if;
  if nrun = 0 then warns := warns || to_jsonb('no_payroll_run'::text); end if;
  if public.rule_on('payroll_accrual_on') and not hooks then warns := warns || to_jsonb('accrual_hook_missing'::text); end if;
  if public.rule_on('payroll_accrual_on') and public._c_accrual_from() is null then warns := warns || to_jsonb('accrual_from_missing'::text); end if;
  if public._c_close_state(m) = 'closed' then blockers := blockers || to_jsonb('already_closed'::text); end if;
  if st is not null then
    select count(*) filter (where d.waiting is null), count(*) filter (where d.waiting is not null) into unposted, waiting
      from public._c_docs(st) d where d.entry_date between m and me and d.source_type in ('payroll_accrual', 'payroll_pay_accr');
    if unposted > 0 then blockers := blockers || to_jsonb('payroll_not_posted'::text); end if;
    if waiting > 0 then blockers := blockers || to_jsonb('advance_recovery_exceeds_balance'::text); end if;
    if me >= st then
      pl := public.acct_income_statement(greatest(m, st), me, null);
      select account_id into sid from public.acct_mappings where key = 'salary_exp';
      select coalesce(sum(b.dr - b.cr), 0) into sal_j from public._acct_bal(greatest(m, st), me, null) b where b.account_id = sid;
      -- every counted run of the month is accrual basis, so the books should carry exactly the run total; a difference is a reversal dated in another month or a manual entry on the salary account
      if coalesce((select bool_and(public._c_run_basis(r.id) = 'accrual') from public.payroll_runs r where r.month = m and r.status in ('approved', 'paid') and not public.is_shadow('payroll_runs', r.id::text)), false)
         and abs(sal_j - sal_exp) > 0.004 then warns := warns || to_jsonb('salary_journal_differs_from_runs'::text); end if;
    end if;
  end if;
  select count(*) into unb from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z;
  if unb > 0 then blockers := blockers || to_jsonb('unbalanced_entries'::text); end if;
  select coalesce(sum(a.amount - coalesce((select sum(r.amount) from public.employee_advance_recoveries r where r.advance_id = a.id and r.status = 'active'), 0)), 0)
    into adv_out from public.employee_advances a where a.status = 'active';
  return jsonb_build_object('month', m, 'to', me, 'state', public._c_close_state(m), 'blockers', blockers, 'warnings', warns, 'can_close', jsonb_array_length(blockers) = 0,
    'payroll', jsonb_build_object('runs', runs, 'salary_expense', sal_exp, 'paid', sal_paid, 'net_pay', sal_net, 'unpaid', sal_net - sal_paid, 'salary_in_journal', sal_j,
                                  'pending_postings', unposted, 'accrual_on', public.rule_on('payroll_accrual_on'), 'accrual_from', public._c_accrual_from(), 'hooks_installed', hooks,
                                  'pay_source', coalesce(public.rule_txt('salary_pay_source'), 'by_payment')),
    'advances', jsonb_build_object('outstanding_all_staff', adv_out),
    'profit', case when pl is null then null else jsonb_build_object('income', pl -> 'total_income', 'expense', pl -> 'total_expense', 'net_profit', pl -> 'net_profit',
                'salary_in_journal', sal_j, 'profit_before_salary', (pl ->> 'net_profit')::numeric + sal_j, 'source', 'journal') end);
end $$;

create or replace function public.c_month_close(p_month date, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date; pv jsonb; sp jsonb; staff text; id_ bigint;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_note is not null and char_length(p_note) > 500 then raise exception 'too_long'; end if;
  perform pg_advisory_xact_lock(hashtextextended('c_month_close', extract(year from m)::int * 100 + extract(month from m)::int));
  pv := public.c_month_close_preview(m);
  if jsonb_array_length(pv -> 'blockers') > 0 then raise exception 'blocked: %', (select string_agg(x, ', ') from jsonb_array_elements_text(pv -> 'blockers') x); end if;
  begin sp := public.c_partner_month_split(m); exception when others then sp := null; end;
  select staff_id into staff from public.profiles where id = auth.uid();
  insert into public.c_month_close_log (month, action, snapshot, note, created_by, created_staff)
    values (m, 'close', pv || jsonb_build_object('partner_split', sp), left(nullif(btrim(p_note), ''), 500), auth.uid(), staff) returning id into id_;
  return jsonb_build_object('id', id_, 'month', m, 'state', 'closed');
end $$;

create or replace function public.c_month_reopen(p_month date, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date; staff text; id_ bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if public._c_close_state(m) <> 'closed' then raise exception 'not_closed'; end if;
  select staff_id into staff from public.profiles where id = auth.uid();
  insert into public.c_month_close_log (month, action, snapshot, note, created_by, created_staff) values (m, 'reopen', null, left(btrim(p_reason), 500), auth.uid(), staff) returning id into id_;
  return jsonb_build_object('id', id_, 'month', m, 'state', 'open');
end $$;

create or replace function public.c_month_closes(p_months int default 12) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare n int := least(greatest(coalesce(p_months, 12), 1), 60);
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('month', z.month, 'state', case when z.action = 'close' then 'closed' else 'open' end, 'at', z.created_at, 'by', z.created_staff, 'note', z.note,
           'net_profit', z.snapshot #> '{profit,net_profit}', 'salary_expense', z.snapshot #> '{payroll,salary_expense}') order by z.month desc)
    from (select distinct on (month) * from public.c_month_close_log order by month, id desc) z
    where z.month >= (date_trunc('month', public._acct_today()) - make_interval(months => n))::date), '[]'::jsonb);
end $$;

-- ---------- 9. partner profit split + share report ----------
create or replace function public.c_partner_month_split(p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date; me date := public._c_me(p_month); st date := public._acct_start(); a record; pc record; out jsonb := '[]'; prof jsonb; base numeric; amts numeric[];
        pcts numeric[]; ids jsonb; parts jsonb; status_ text; missing int; npart int; settled numeric;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if st is null or me < st then return jsonb_build_object('month', m, 'data_needed', true, 'agreements', '[]'::jsonb); end if;
  for a in select ag.id, ag.title, v.id venture_id, v.scope, v.location_id from public.partner_agreements ag join public.partner_ventures v on v.id = ag.venture_id
            where ag.status = 'active' and ag.effective_from <= me and (ag.effective_to is null or ag.effective_to >= m) order by ag.id loop
    prof := public.acct_income_statement(greatest(m, st), me, case when a.scope = 'location' then a.location_id end);
    base := (prof ->> 'net_profit')::numeric;
    select count(*) filter (where ap.share_percent is null), count(*) into missing, npart
      from public.agreement_parties ap where ap.agreement_id = a.id and ap.active and ap.role in ('owner', 'partner', 'investor', 'franchisee');
    parts := '[]'; pcts := '{}'; status_ := 'ok'; amts := null;
    if npart = 0 then status_ := 'no_shares';
    elsif missing > 0 then status_ := 'share_missing';
    else
      select array_agg(ap.share_percent order by ap.id) into pcts from public.agreement_parties ap
       where ap.agreement_id = a.id and ap.active and ap.role in ('owner', 'partner', 'investor', 'franchisee');
      if abs((select sum(x) from unnest(pcts) x) - 100) > 0.0001 then status_ := 'shares_not_100';
      elsif base <= 0 then status_ := case when base < 0 then 'loss_month' else 'no_profit' end;
      else amts := public._c_split(base, pcts); end if;
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('party_id', z.party_id, 'name', z.name, 'role', z.role, 'share_percent', z.share_percent,
             'amount', case when amts is not null then amts[z.rn::int] end) order by z.rn), '[]'::jsonb)
      into parts from (select ap.party_id, pp.name, ap.role, ap.share_percent, row_number() over (order by ap.id) rn
                         from public.agreement_parties ap join public.partner_parties pp on pp.id = ap.party_id
                        where ap.agreement_id = a.id and ap.active and ap.role in ('owner', 'partner', 'investor', 'franchisee')) z;
    select coalesce(sum(s.total_distributable), 0) into settled from public.partner_settlements s
     where s.agreement_id = a.id and s.status <> 'void' and s.period_from <= me and s.period_to >= m;
    out := out || jsonb_build_object('agreement_id', a.id, 'title', a.title, 'venture_id', a.venture_id, 'scope', a.scope, 'location_id', case when a.scope = 'location' then a.location_id end,
      'status', status_, 'base_profit', base, 'distributable', case when amts is not null then base end, 'parties', parts, 'settlement_total_in_month', settled);
  end loop;
  return jsonb_build_object('month', m, 'basis', 'journal net profit of the month (salary accrual included)', 'agreements', out,
    'note', 'Preview by the share percent written in each agreement. The contract rules (royalty, fees, tiers) are in the settlement, which is what posts to the books.');
end $$;

-- per-partner share report: settlement lines, paid, outstanding, and what the books carry on the payable account for this partner
create or replace function public.c_partner_share_report(p_party bigint, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pa bigint; rows jsonb; books numeric := 0; acc_out numeric := 0; tot_a numeric := 0; tot_p numeric := 0;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  select account_id into pa from public.acct_mappings where key = 'partner_payable';
  select coalesce(jsonb_agg(jsonb_build_object('settlement_id', s.id, 'period_from', s.period_from, 'period_to', s.period_to, 'status', s.status, 'kind', l.kind, 'amount', l.amount,
           'paid', l.paid_amount, 'outstanding', l.amount - l.paid_amount, 'funded_outside', l.funded_outside, 'basis', public._c_settle_basis(s.id)) order by s.period_from, s.id, l.id), '[]'::jsonb),
         coalesce(sum(l.amount) filter (where s.status in ('approved', 'paid') and not l.funded_outside), 0),
         coalesce(sum(l.paid_amount) filter (where s.status in ('approved', 'paid') and not l.funded_outside), 0),
         coalesce(sum(l.amount - l.paid_amount) filter (where s.status in ('approved', 'paid') and not l.funded_outside and public._c_settle_basis(s.id) = 'accrual'), 0)
    into rows, tot_a, tot_p, acc_out
    from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id
   where l.party_id = p_party and s.status <> 'void' and (p_from is null or s.period_to >= p_from) and (p_to is null or s.period_from <= p_to);
  select coalesce(sum(jl.credit - jl.debit), 0) into books from public.journal_lines jl where jl.account_id = pa and jl.party_type = 'partner' and jl.party_id = p_party::text;
  return jsonb_build_object('party_id', p_party, 'lines', rows, 'approved_total', tot_a, 'paid_total', tot_p, 'outstanding_accrual_basis', acc_out, 'payable_in_books', books);
end $$;

-- every partner: is the payable account equal to the unpaid part of the approved settlements?
create or replace function public.c_partner_payable_check() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pa bigint;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  select account_id into pa from public.acct_mappings where key = 'partner_payable';
  return coalesce((select jsonb_agg(jsonb_build_object('party_id', z.pid, 'books', z.books, 'settlements', z.owed, 'difference', z.books - z.owed) order by z.pid)
    from (select coalesce(b.pid, o.pid) pid, coalesce(b.books, 0) books, coalesce(o.owed, 0) owed
            from (select jl.party_id::bigint pid, sum(jl.credit - jl.debit) books from public.journal_lines jl where jl.account_id = pa and jl.party_type = 'partner' group by 1) b
            full join (select l.party_id pid, sum(l.amount - l.paid_amount) owed from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id
                        where s.status in ('approved', 'paid') and not l.funded_outside and public._c_settle_basis(s.id) = 'accrual' group by 1) o on o.pid = b.pid) z), '[]'::jsonb);
end $$;

-- ---------- 10. grants ----------
revoke all on function public._c_docs(date), public._c_run_basis(bigint), public._c_accrual_covers(bigint), public._c_run_skip(bigint), public._c_salary_paykey(text),
  public._c_settle_basis(bigint), public._c_hooks_ok(), public._c_accrual_from(), public._c_accrual_lines(bigint, int), public._c_close_state(date), public._c_split(numeric, numeric[]),
  public._c_me(date) from public, anon, authenticated;
revoke all on function public.c_post_pending(boolean, int), public.c_daily_profit(date, date, int), public.c_month_close_preview(date), public.c_month_close(date, text),
  public.c_month_reopen(date, text), public.c_month_closes(int), public.c_partner_month_split(date), public.c_partner_share_report(bigint, date, date), public.c_partner_payable_check(),
  public.c_salary_pay_default() from public, anon;
grant execute on function public.c_post_pending(boolean, int), public.c_daily_profit(date, date, int), public.c_month_close_preview(date), public.c_month_close(date, text),
  public.c_month_reopen(date, text), public.c_month_closes(int), public.c_partner_month_split(date), public.c_partner_share_report(bigint, date, date), public.c_partner_payable_check(),
  public.c_salary_pay_default() to authenticated;
