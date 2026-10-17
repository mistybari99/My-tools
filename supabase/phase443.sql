-- Phase 443 (bos443) - STATEMENTS, part 1 (package RPT-C1, block R3): account classes and the P&L by month and outlet. Paste AFTER phase442. Paste-twice safe. New objects only.
-- WHY (docs/REPORTS_AUDIT_3.md reports 121, 124, 126): the books can show ONE P&L for ONE period and ONE place at a time; the cash-flow tab is a list of cash-account movements without
--      operating / investing / financing, and there is no working-capital figure. The owner decides which class each chart account belongs to; nothing is guessed.
-- WHAT THIS FILE DOES (read only for the books: no journal line is written)
--   1. Table coa_report_class: per chart account, an optional cash-flow class (operating / investing / financing) and an optional balance class (current / non_current). BLANK = "unclassified".
--      Nothing is deleted (clearing a class blanks it; every change is written to audit_log by the table trigger). Set by the owner or an accounts manager: coa_class_set, coa_class_apply_suggested.
--      coa_class_list shows every account with its classes AND a suggestion (usual accounting practice by account code); a suggestion is never applied by itself - only coa_class_apply_suggested
--      (owner / accounts manager, fills blanks only, never overwrites) applies it.
--   2. stmt_pl_matrix(from, to, place): the P&L from the JOURNAL by month (columns) and outlet (rows): income, cost of goods, other expenses, gross and net. Year-end closing journals are left out.
--      Journal lines without an outlet are shown on their own row ("not assigned to an outlet"). stmt_pl_drill(month, place, kind): the accounts and the biggest journal entries behind one cell.
-- Access: owner, accounts view / manage right, or the report grant of the profit group. Places: the ones the person may see (same rule as the books). Needs the accounting start date; without it
--      the answer says so ("accounting module not switched on - no data captured") and carries no number.

do $g$ begin
  if to_regprocedure('public._c1_p442_present()') is null then raise exception 'phase443 needs phase442 first'; end if;
  if to_regclass('public.coa_accounts') is null or to_regprocedure('public._acct_bal(date,date,integer)') is null or to_regprocedure('public._w1d_mgr()') is null then
    raise exception 'phase443 needs the accounting of phases 40 and 92';
  end if;
end $g$;

create or replace function public._c1_p443_present() returns boolean language sql immutable as $$ select true $$;

create or replace function public._stmt_view() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._acct_view() or public.rpt_access('profit')) $$;

-- ---------- 1. classes per account ----------
create table if not exists public.coa_report_class (
  account_id bigint primary key references public.coa_accounts(id),
  cf_class text check (cf_class in ('operating', 'investing', 'financing')),
  bs_class text check (bs_class in ('current', 'non_current')),
  reason text check (reason is null or length(reason) <= 300),
  set_by uuid default auth.uid(), set_at timestamptz not null default now()
);
drop trigger if exists coa_report_class_nodel on public.coa_report_class;
create trigger coa_report_class_nodel before delete on public.coa_report_class for each row execute function public.no_hard_delete();
drop trigger if exists audit_coa_report_class on public.coa_report_class;
create trigger audit_coa_report_class after insert or update on public.coa_report_class for each row execute function public.log_change('account_id');
alter table public.coa_report_class enable row level security;
revoke all on public.coa_report_class from public, anon, authenticated;
drop policy if exists coa_report_class_read on public.coa_report_class;
create policy coa_report_class_read on public.coa_report_class for select to authenticated using (public._stmt_view());
grant select on public.coa_report_class to authenticated;

-- the cash accounts: the SAME set the Cash flow tab (acct_cash_flow) uses, so the two agree
create or replace function public._c1_cash_ids() returns bigint[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct x), '{}') from (
    select account_id x from public.acct_mappings where key in ('pay_cash', 'pay_bank', 'pay_mobile')
    union select coa_account_id from public.money_accounts
    union select account_id from public.acct_mappings where key like 'd\_wallet\_%') z where x is not null $$;

-- usual practice by account code (a suggestion only). cf: income / expense and the working accounts are operating, fixed assets investing, partner loans and capital financing.
-- bs: assets are current except the fixed-asset group 15xx; liabilities are current except partner loans 25xx (left blank: the owner decides).
create or replace function public._c1_class_suggest(p_code text, p_type text) returns table (cf text, bs text) language sql immutable set search_path = public as $$
  select case
           when p_type in ('income', 'expense') then 'operating'
           when p_type = 'asset' and p_code ~ '^1[234]' then 'operating'
           when p_type = 'asset' and p_code ~ '^15' then 'investing'
           when p_type = 'liability' and p_code ~ '^25' then 'financing'
           when p_type = 'liability' then 'operating'
           when p_type = 'equity' and p_code ~ '^3[1-4]' then 'financing'
           else null end,
         case
           when p_type = 'asset' and p_code ~ '^15' then 'non_current'
           when p_type = 'asset' then 'current'
           when p_type = 'liability' and p_code ~ '^25' then null
           when p_type = 'liability' then 'current'
           else null end $$;

create or replace function public.coa_class_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ids bigint[] := public._c1_cash_ids();
begin
  if not public._stmt_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'type', a.type, 'active', a.active, 'is_cash', a.id = any (ids),
      'cf_class', c.cf_class, 'bs_class', c.bs_class, 'suggest_cf', s.cf, 'suggest_bs', s.bs, 'set_at', c.set_at, 'reason', c.reason) order by a.code)
    from public.coa_accounts a left join public.coa_report_class c on c.account_id = a.id
    cross join lateral public._c1_class_suggest(a.code, a.type) s
    where not a.is_group), '[]'::jsonb);
end $$;

create or replace function public.coa_class_set(p_account bigint, p_cf text, p_bs text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.coa_accounts; cf text := nullif(btrim(coalesce(p_cf, '')), ''); bs text := nullif(btrim(coalesce(p_bs, '')), ''); why text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public._w1d_mgr() then raise exception 'not allowed'; end if;
  select * into a from public.coa_accounts where id = p_account;
  if not found then raise exception 'account_not_found'; end if;
  if a.is_group then raise exception 'account_is_group'; end if;
  if cf is not null and cf not in ('operating', 'investing', 'financing') then raise exception 'bad_value'; end if;
  if bs is not null and bs not in ('current', 'non_current') then raise exception 'bad_value'; end if;
  if cf is not null and p_account = any (public._c1_cash_ids()) then raise exception 'cash_account_has_no_flow_class'; end if;
  if bs is not null and a.type not in ('asset', 'liability') then raise exception 'balance_class_is_for_assets_and_liabilities'; end if;
  if why is not null and length(why) > 300 then raise exception 'too_long'; end if;
  insert into public.coa_report_class (account_id, cf_class, bs_class, reason, set_by, set_at) values (p_account, cf, bs, why, auth.uid(), now())
    on conflict (account_id) do update set cf_class = excluded.cf_class, bs_class = excluded.bs_class, reason = excluded.reason, set_by = auth.uid(), set_at = now();
  return jsonb_build_object('account_id', p_account, 'cf_class', cf, 'bs_class', bs);
end $$;

-- fills the blanks with the suggestion. Never overwrites a class that is set. Dry run (p_dry true, the default) writes nothing and says what it would do.
create or replace function public.coa_class_apply_suggested(p_reason text default null, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int := 0; x record; ids bigint[] := public._c1_cash_ids(); why text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public._w1d_mgr() then raise exception 'not allowed'; end if;
  if not coalesce(p_dry, true) and (why is null or length(why) < 5) then raise exception 'reason_required'; end if;
  for x in select a.id, a.code, c.cf_class cur_cf, c.bs_class cur_bs, s.cf, s.bs, (a.id = any (ids)) is_cash
             from public.coa_accounts a left join public.coa_report_class c on c.account_id = a.id cross join lateral public._c1_class_suggest(a.code, a.type) s
            where not a.is_group and ((c.cf_class is null and s.cf is not null and not (a.id = any (ids))) or (c.bs_class is null and s.bs is not null)) loop
    n := n + 1;
    if not coalesce(p_dry, true) then
      insert into public.coa_report_class (account_id, cf_class, bs_class, reason, set_by, set_at)
        values (x.id, case when x.is_cash then null else x.cur_cf end, x.cur_bs, null, auth.uid(), now()) on conflict (account_id) do nothing;
      update public.coa_report_class c set cf_class = coalesce(c.cf_class, case when x.is_cash then null else x.cf end), bs_class = coalesce(c.bs_class, x.bs),
             reason = coalesce(why, c.reason), set_by = auth.uid(), set_at = now() where c.account_id = x.id;
    end if;
  end loop;
  return jsonb_build_object('dry', coalesce(p_dry, true), 'accounts', n);
end $$;

-- ---------- 2. P&L by month and outlet, from the journal ----------
create or replace function public.stmt_pl_matrix(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); to_ date := coalesce(p_to, public._acct_today()); fr date; v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs();
  cid bigint; cells jsonb; outs jsonb; by_m jsonb; by_o jsonb; grand jsonb; months jsonb; ncl bigint; nun bigint; cm bigint;
begin
  if not public._stmt_view() then raise exception 'not allowed'; end if;
  if st is null then
    return jsonb_build_object('data_needed', true, 'reason', 'accounting_not_started', 'text_en', 'The accounting module is not switched on (no start date) - no data captured.',
      'text_bn', 'হিসাব মডিউল চালু নেই (শুরুর তারিখ নেই) - কোনো তথ্য সংগ্রহ হয়নি।');
  end if;
  fr := coalesce(p_from, st);
  if fr > to_ or to_ - fr > 1100 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select account_id into cid from public.acct_mappings where key = 'cogs';
  select coalesce(jsonb_agg(to_char(m, 'YYYY-MM') order by m), '[]'::jsonb) into months from generate_series(date_trunc('month', fr), date_trunc('month', to_), interval '1 month') m;

  with p as (
    select to_char(date_trunc('month', e.entry_date), 'YYYY-MM') as mon, l.location_id as loc,
           coalesce(sum(l.credit - l.debit) filter (where a.type = 'income'), 0) as income,
           coalesce(sum(l.debit - l.credit) filter (where a.id = cid), 0) as cogs,
           coalesce(sum(l.debit - l.credit) filter (where a.type = 'expense' and a.id is distinct from cid), 0) as expenses
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
     where a.type in ('income', 'expense') and not a.is_group and e.entry_date between fr and to_
       and e.source_type <> 'year_close' and coalesce(e.flags, '') not like '%year_close%'
       and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
     group by 1, 2),
  c as (select coalesce(jsonb_agg(jsonb_build_object('month', p.mon, 'location_id', p.loc, 'income', p.income, 'cogs', p.cogs, 'gross', p.income - p.cogs, 'expenses', p.expenses, 'net', p.income - p.cogs - p.expenses,
          'cogs_missing', (select count(*) from public.journal_entries e where to_char(date_trunc('month', e.entry_date), 'YYYY-MM') = p.mon and e.flags like '%cogs_missing%' and e.reverses_id is null
                            and e.location_id is not distinct from p.loc)) order by p.mon, p.loc nulls last), '[]'::jsonb) j from p),
  o as (select coalesce(jsonb_agg(jsonb_build_object('location_id', z.loc, 'name_bn', coalesce(lc.name_bn, 'কোনো আউটলেটে দেওয়া নেই'), 'name_en', coalesce(lc.name_en, lc.name_bn, 'Not assigned to an outlet'),
          'assigned', z.loc is not null) order by z.loc nulls last), '[]'::jsonb) j from (select distinct loc from p) z left join public.locations lc on lc.id = z.loc),
  bm as (select coalesce(jsonb_agg(jsonb_build_object('month', q.mon, 'income', q.i, 'cogs', q.c, 'gross', q.i - q.c, 'expenses', q.x, 'net', q.i - q.c - q.x) order by q.mon), '[]'::jsonb) j
           from (select mon, sum(income) i, sum(cogs) c, sum(expenses) x from p group by mon) q),
  bo as (select coalesce(jsonb_agg(jsonb_build_object('location_id', q.loc, 'income', q.i, 'cogs', q.c, 'gross', q.i - q.c, 'expenses', q.x, 'net', q.i - q.c - q.x) order by q.loc nulls last), '[]'::jsonb) j
           from (select loc, sum(income) i, sum(cogs) c, sum(expenses) x from p group by loc) q),
  gr as (select jsonb_build_object('income', coalesce(sum(income), 0), 'cogs', coalesce(sum(cogs), 0), 'gross', coalesce(sum(income - cogs), 0), 'expenses', coalesce(sum(expenses), 0),
          'net', coalesce(sum(income - cogs - expenses), 0)) j, count(*) filter (where loc is null) as nun from p)
  select c.j, o.j, bm.j, bo.j, gr.j, gr.nun into cells, outs, by_m, by_o, grand, nun from c, o, bm, bo, gr;

  select count(*) into ncl from public.journal_entries e where e.entry_date between fr and to_ and (e.source_type = 'year_close' or coalesce(e.flags, '') like '%year_close%');
  select count(*) into cm from public.journal_entries e where e.entry_date between fr and to_ and e.flags like '%cogs_missing%' and e.reverses_id is null
     and (v_all or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc);
  return jsonb_build_object('from', fr, 'to', to_, 'location_id', p_loc, 'months', months, 'outlets', outs, 'cells', cells, 'by_month', by_m, 'by_outlet', by_o, 'grand', grand,
    'provisional', cm > 0, 'cogs_missing_entries', cm,
    'notes', (case when ncl > 0 then jsonb_build_array(jsonb_build_object('code', 'year_close_left_out', 'level', 'info', 'n', ncl,
                 'text_en', 'Year-end closing journals (' || ncl || ') are left out so that the closed year still shows its income and expenses.', 'text_bn', 'বছর শেষের ক্লোজিং জার্নাল (' || ncl || 'টি) বাদ দেওয়া হয়েছে, যাতে ক্লোজ করা বছরেও আয় ও খরচ দেখা যায়।')) else '[]'::jsonb end)
      || (case when nun > 0 then jsonb_build_array(jsonb_build_object('code', 'unassigned_outlet', 'level', 'info', 'text_en', 'Some journal lines have no outlet; they are on their own row.', 'text_bn', 'কিছু জার্নাল লাইনে আউটলেট নেই; সেগুলো আলাদা সারিতে।')) else '[]'::jsonb end)
      || (case when cm > 0 then jsonb_build_array(jsonb_build_object('code', 'cogs_missing', 'level', 'warn', 'n', cm, 'text_en', cm || ' sale(s) have no known cost in the books: the gross profit is provisional.', 'text_bn', cm || 'টি বিক্রির খাতায় খরচ জানা নেই: মোট লাভ সাময়িক।')) else '[]'::jsonb end),
    'basis', jsonb_build_object('text_en', 'From the journal (the books). Income is net of sales returns and discounts; cost of goods is the cost-of-goods account; other expenses are all other expense accounts. It is not the management view of the hub reports.',
      'text_bn', 'জার্নাল (হিসাবের খাতা) থেকে। আয় বিক্রি-ফেরত ও ছাড় বাদে; মালের খরচ মালের খরচের অ্যাকাউন্ট; অন্য খরচ বাকি সব খরচের অ্যাকাউন্ট। এটি হাবের রিপোর্টের ম্যানেজমেন্ট ভিউ নয়।'));
end $$;

create or replace function public.stmt_pl_drill(p_month date, p_loc int, p_kind text, p_unassigned boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); m0 date; m1 date; v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); cid bigint; accs jsonb; ents jsonb;
  kind text := lower(coalesce(nullif(btrim(p_kind), ''), 'all'));
begin
  if not public._stmt_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_month is null or kind not in ('income', 'cogs', 'expenses', 'all') then raise exception 'bad_value'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  m0 := date_trunc('month', p_month)::date; m1 := (m0 + interval '1 month')::date - 1;
  select account_id into cid from public.acct_mappings where key = 'cogs';
  with d as (
    select a.id as aid, e.id as eid, case when a.type = 'income' then l.credit - l.debit else l.debit - l.credit end as amt,
           case when a.type = 'income' then 'income' when a.id = cid then 'cogs' else 'expenses' end as typ
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
     where a.type in ('income', 'expense') and not a.is_group and e.entry_date between greatest(m0, st) and m1 and e.source_type <> 'year_close' and coalesce(e.flags, '') not like '%year_close%'
       and (v_all or l.location_id = any (v_locs))
       and ((coalesce(p_unassigned, false) and l.location_id is null) or (not coalesce(p_unassigned, false) and (p_loc is null or l.location_id = p_loc)))),
  fa as (select aid, typ, sum(amt) amt, count(*) n from d where kind = 'all' or typ = kind group by aid, typ),
  fe as (select eid, typ, sum(amt) amt from d where kind = 'all' or typ = kind group by eid, typ order by abs(sum(amt)) desc limit 100)
  select (select coalesce(jsonb_agg(jsonb_build_object('account_id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'kind', fa.typ, 'amount', fa.amt, 'lines', fa.n) order by fa.typ, a.code), '[]'::jsonb)
            from fa join public.coa_accounts a on a.id = fa.aid),
         (select coalesce(jsonb_agg(jsonb_build_object('entry_id', je.id, 'entry_date', je.entry_date, 'source_type', je.source_type, 'memo', je.memo, 'kind', fe.typ, 'amount', fe.amt) order by abs(fe.amt) desc, je.id), '[]'::jsonb)
            from fe join public.journal_entries je on je.id = fe.eid)
    into accs, ents;
  return jsonb_build_object('month', to_char(m0, 'YYYY-MM'), 'location_id', p_loc, 'unassigned', coalesce(p_unassigned, false), 'kind', kind, 'accounts', accs, 'entries', ents);
end $$;

revoke all on function public._stmt_view(), public._c1_cash_ids(), public._c1_class_suggest(text, text) from public, anon, authenticated;
grant execute on function public._stmt_view() to authenticated;       -- used by the table policy
revoke all on function public.coa_class_list(), public.coa_class_set(bigint, text, text, text), public.coa_class_apply_suggested(text, boolean),
  public.stmt_pl_matrix(date, date, int), public.stmt_pl_drill(date, int, text, boolean) from public, anon;
grant execute on function public.coa_class_list(), public.coa_class_set(bigint, text, text, text), public.coa_class_apply_suggested(text, boolean),
  public.stmt_pl_matrix(date, date, int), public.stmt_pl_drill(date, int, text, boolean) to authenticated;
notify pgrst, 'reload schema';
