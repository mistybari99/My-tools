-- Phase 442 (bos442) - EXPENSE REGISTER (package RPT-C1, block R2). Paste AFTER phase441. Paste-twice safe. New functions only: nothing that exists is edited.
-- WHY (docs/REPORTS_AUDIT_3.md F3, F8, reports 114 and 115): the same period shows three different expense totals (expense report 790, P&L and day book 1,210, journal 920 in the dry run) and no screen
--      lists the vouchers behind them; the marketing register (18-1) is read by two reports and reaches no total at all.
-- WHAT THIS FILE DOES (read only: no record and no journal line is written; no new setting; the existing settings expense_count_on, report_expense_parity_on and d_wallet_fee_treatment decide the flags)
--   expense_register(from, to, place, basis, kinds, status, limit, offset): ONE list, one line per voucher:
--      expense vouchers 10-2 (every status), quick expenses, bank charges, mobile wallet fees, and the marketing register 18-1 lines marked "not in the books".
--      Every line says whether it is counted by the expense report, by the P&L and day book, and by the journal (and whether the journal line is posted yet).
--      basis = all | report | pl | journal: the list shows only the lines that basis counts (all = every line).
--      The answer also carries the reconciliation: the three totals, and for every kind of line how much of it each total counts and why they differ.
-- Access: owner, or the report grant of the expense group (report_expense / view_reports), or the accounts view right. Places: the ones the person may see. Nothing depends on a capture switch.

do $g$ begin
  if to_regprocedure('public._c1_p441_present()') is null then raise exception 'phase442 needs phase441 first'; end if;
  if to_regclass('public.quick_expenses') is null or to_regclass('public.money_charges') is null or to_regclass('public.d_wallet_fees') is null
     or to_regprocedure('public._w1d_exp_status_ok(text,text)') is null or to_regprocedure('public._w1d_parity_on()') is null then
    raise exception 'phase442 needs the tables and functions of phases 50, 83, 87 and 93';
  end if;
end $g$;

create or replace function public._c1_p442_present() returns boolean language sql immutable as $$ select true $$;

create or replace function public._c1_exp_view() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_access('expense') or public._acct_view()) $$;

-- is there a live (not reversed) journal entry for this document?
create or replace function public._c1_je_live(p_type text, p_id text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.journal_entries je where je.source_type = p_type and je.source_id = p_id and je.reverses_id is null
                   and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id)) $$;

-- every expense line of the period and places, with the three flags. Internal: the caller checks the right and the places.
create or replace function public._c1_exp_rows(p_from date, p_to date, p_locs int[])
returns table (key text, kind text, class text, source_id text, entry_date date, location_id int, ref text, head text, heads jsonb, paid_to text, mode text, amount numeric, status text,
               no_receipt_amount numeric, unreadable int, in_report boolean, in_pl boolean, in_journal boolean, posted boolean, flags text[], staff text)
language sql stable security definer set search_path = public as $$
  with par as (select public._w1d_parity_on() as par_on, coalesce(public.rule_txt('d_wallet_fee_treatment'), 'separate_expense') as wf),
  v as (
    select e.id, e.serial, e.entry_date, e.location_id, e.status, e.created_staff, e.rev_no, public.is_shadow('entries', e.id::text) as shadow, z.*
      from public.entries e
      cross join lateral (
        select coalesce(sum(public._r2_num(ln -> 'amount')), 0) as amt,
               coalesce(sum(public._r2_num(ln -> 'amount')) filter (where ln ->> 'receipt' = 'no'), 0) as norc,
               count(*) filter (where coalesce(btrim(ln ->> 'amount'), '') <> '' and public._r2_num(ln -> 'amount') is null) as bad,
               count(distinct coalesce(nullif(btrim(ln ->> 'head'), ''), '-')) as nh,
               min(coalesce(nullif(btrim(ln ->> 'head'), ''), '-')) as h1,
               min(nullif(btrim(ln ->> 'to'), '')) as to1,
               coalesce(jsonb_agg(jsonb_build_object('head', coalesce(nullif(btrim(ln ->> 'head'), ''), '-'), 'to', nullif(btrim(ln ->> 'to'), ''), 'receipt', ln ->> 'receipt', 'amount', public._r2_num(ln -> 'amount')) order by ord), '[]'::jsonb) as lines
          from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) with ordinality as t(ln, ord)) z
     where e.form_code = '10-2' and e.entry_date between p_from and p_to and e.location_id = any (p_locs))
  select 'voucher:' || v.id::text, 'voucher'::text,
         (case when v.shadow then 'voucher_shadow' when v.status = 'approved' then 'voucher_approved' when v.status = 'submitted' then 'voucher_submitted' else 'voucher_not_counted' end)::text,
         v.id::text, v.entry_date, v.location_id, v.serial::text, (case when v.nh = 1 then v.h1 end)::text, v.lines, v.to1::text, null::text, v.amt, v.status::text, v.norc, v.bad::int,
         (public._w1d_exp_status_ok(v.status, 'pl') and (not (select par_on from par) or not v.shadow)),
         (public._w1d_exp_status_ok(v.status, 'pl') and not v.shadow),
         (public._w1d_exp_status_ok(v.status, 'journal') and not v.shadow),
         public._c1_je_live('expense_voucher', v.id::text || ':' || coalesce(v.rev_no, 0)::text),
         array_remove(array[case when v.shadow then 'shadow' end, case when v.bad > 0 then 'unreadable_lines' end, case when v.norc > 0 then 'no_receipt' end], null)::text[],
         v.created_staff::text
    from v
  union all
  select 'quick:' || q.id::text, 'quick', 'quick', q.id::text, q.exp_date, q.location_id, null::text, q.head::text, null::jsonb, nullif(btrim(q.paid_to), '')::text, q.mode::text, q.amount, q.status::text,
         (case when not q.receipt then q.amount else 0 end)::numeric, 0,
         (q.status = 'done' and (select par_on from par)), (q.status = 'done'), (q.status = 'done'), public._c1_je_live('quick_expense', q.id::text),
         array_remove(array[case when not q.receipt then 'no_receipt' end], null)::text[], q.created_staff::text
    from public.quick_expenses q where q.exp_date between p_from and p_to and q.location_id = any (p_locs)
  union all
  select 'bank_charge:' || c.id::text, 'bank_charge', 'bank_charge', c.id::text, c.charge_date, c.location_id, c.ref::text, null::text, null::jsonb, coalesce(nullif(btrim(ma.name_en), ''), ma.name_bn)::text, ma.kind::text, c.amount, c.status::text,
         0::numeric, 0, false, false, (c.status = 'done'), public._c1_je_live('money_charge', c.id::text), '{}'::text[], c.created_staff::text
    from public.money_charges c join public.money_accounts ma on ma.id = c.account_id
   where c.kind = 'charge' and c.charge_date between p_from and p_to and (c.location_id = any (p_locs) or (c.location_id is null and public._acct_all()))
  union all
  select 'wallet_fee:' || f.id::text, 'wallet_fee', 'wallet_fee', f.id::text, f.fee_date, f.location_id, f.ref::text, f.kind::text, null::jsonb, w.name_en::text, 'mobile'::text, f.amount, (case when f.voided then 'void' else 'done' end)::text,
         0::numeric, 0, false, (not f.voided and (select wf from par) = 'separate_expense'), (not f.voided and (select wf from par) = 'separate_expense'), public._c1_je_live('d_wallet_fee', f.id::text),
         '{}'::text[], f.created_staff::text
    from public.d_wallet_fees f join public.d_wallets w on w.id = f.wallet_id
   where f.fee_date between p_from and p_to and (f.location_id = any (p_locs) or (f.location_id is null and public._acct_all()))
  union all
  select ('marketing:' || e.id::text || ':' || t.ord::text), 'marketing', 'marketing', e.id::text, coalesce(public._db_date(ln ->> 'date'), e.entry_date), e.location_id, e.serial::text,
         coalesce(nullif(btrim(ln ->> 'head'), ''), '-')::text, null::jsonb, nullif(btrim(ln ->> 'campaign'), '')::text, nullif(btrim(ln ->> 'source'), '')::text, public._r2_num(ln -> 'amt'), e.status::text,
         0::numeric, 0, false, false, false, null::boolean,
         array_remove(array['not_in_books', case when ln ->> 'source' = 'imprest' then 'maybe_in_voucher' end], null)::text[], e.created_staff::text
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) with ordinality as t(ln, ord)
   where e.form_code = '18-1' and e.status in ('submitted', 'approved') and e.location_id = any (p_locs)
     and coalesce(public._db_date(ln ->> 'date'), e.entry_date) between p_from and p_to and coalesce(public._r2_num(ln -> 'amt'), 0) > 0
$$;

create or replace function public.expense_register(p_from date, p_to date, p_loc int default null, p_basis text default 'all', p_kinds text[] default null, p_status text default null,
                                                   p_limit int default 100, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; basis text := lower(coalesce(nullif(btrim(p_basis), ''), 'all')); lim int := least(greatest(coalesce(p_limit, 100), 1), 500); off int := greatest(coalesce(p_offset, 0), 0);
  cnt bigint; shown numeric; rows_ jsonb; lines_ jsonb; tot jsonb; unp jsonb; labels jsonb; sm_en text; sm_bn text; par boolean := public._w1d_parity_on(); cnt_rule text := coalesce(public.rule_txt('expense_count_on'), 'as_today');
  wf text := coalesce(public.rule_txt('d_wallet_fee_treatment'), 'separate_expense');
begin
  if not public._c1_exp_view() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  if basis not in ('all', 'report', 'pl', 'journal') then raise exception 'bad_basis'; end if;
  locs := public._r2_locs(case when p_loc is null then '{}'::jsonb else jsonb_build_object('locations', jsonb_build_array(p_loc)) end);
  if cardinality(locs) = 0 then raise exception 'not allowed'; end if;

  with r as (select * from public._c1_exp_rows(p_from, p_to, locs)),
  f as (select * from r where (basis = 'all' or (basis = 'report' and in_report) or (basis = 'pl' and in_pl) or (basis = 'journal' and in_journal))
                         and (p_kinds is null or kind = any (p_kinds)) and (p_status is null or status = p_status)),
  pg as (select * from f order by entry_date desc, kind, ref nulls last, key limit lim offset off)
  select (select count(*) from f), (select coalesce(sum(amount), 0) from f),
         (select coalesce(jsonb_agg(to_jsonb(pg) order by pg.entry_date desc, pg.kind, pg.ref nulls last, pg.key), '[]'::jsonb) from pg)
    into cnt, shown, rows_;

  with r as (select * from public._c1_exp_rows(p_from, p_to, locs))
  select jsonb_build_object('report', coalesce(sum(amount) filter (where in_report), 0), 'pl', coalesce(sum(amount) filter (where in_pl), 0), 'journal', coalesce(sum(amount) filter (where in_journal), 0),
           'daybook', coalesce(sum(amount) filter (where in_pl and kind <> 'wallet_fee'), 0), 'journal_posted', coalesce(sum(amount) filter (where in_journal and posted), 0), 'not_in_books', coalesce(sum(amount) filter (where kind = 'marketing'), 0),
           'lines', count(*)),
         jsonb_build_object('n', count(*) filter (where in_journal and not posted), 'amount', coalesce(sum(amount) filter (where in_journal and not posted), 0))
    into tot, unp from r;

  with r as (select * from public._c1_exp_rows(p_from, p_to, locs)),
  g as (select class, count(*) n, coalesce(sum(amount), 0) amt, coalesce(sum(amount) filter (where in_report), 0) rep, coalesce(sum(amount) filter (where in_pl), 0) pl,
               coalesce(sum(amount) filter (where in_journal), 0) jr, bool_and(in_report) a_rep, bool_and(in_pl) a_pl, bool_and(in_journal) a_jr from r group by class)
  select coalesce(jsonb_agg(jsonb_build_object('class', g.class, 'n', g.n, 'amount', g.amt, 'report', g.rep, 'pl', g.pl, 'journal', g.jr, 'd_pl_report', g.pl - g.rep, 'd_journal_pl', g.jr - g.pl,
    'label_en', case g.class when 'voucher_approved' then 'Expense vouchers, approved' when 'voucher_submitted' then 'Expense vouchers, submitted and waiting for approval'
        when 'voucher_not_counted' then 'Expense vouchers, draft or rejected' when 'voucher_shadow' then 'Expense vouchers that are a copy (shadow) of another record' when 'quick' then 'Quick expenses'
        when 'bank_charge' then 'Bank charges' when 'wallet_fee' then 'Mobile wallet fees' else 'Marketing register 18-1' end,
    'label_bn', case g.class when 'voucher_approved' then 'ব্যয় ভাউচার, অনুমোদিত' when 'voucher_submitted' then 'ব্যয় ভাউচার, জমা দেওয়া, অনুমোদনের অপেক্ষায়'
        when 'voucher_not_counted' then 'ব্যয় ভাউচার, খসড়া বা বাতিল' when 'voucher_shadow' then 'অন্য রেকর্ডের কপি (শ্যাডো) ভাউচার' when 'quick' then 'দ্রুত খরচ'
        when 'bank_charge' then 'ব্যাংক চার্জ' when 'wallet_fee' then 'মোবাইল ওয়ালেট ফি' else 'মার্কেটিং রেজিস্টার ১৮-১' end,
    'why_en', case g.class
        when 'voucher_approved' then null
        when 'voucher_submitted' then case when g.a_pl then 'Submitted but not yet approved. The expense report, the P&L and the day book count it' else 'Submitted but not yet approved. Nothing counts it yet (the setting counts only approved vouchers)' end
                                      || case when g.a_jr then ', and so does the journal.' else '; the journal waits for the approval.' end
        when 'voucher_not_counted' then 'Draft or rejected: no total counts it.'
        when 'voucher_shadow' then 'A copy of a record that is entered through another path: the main record is counted, this copy is not.'
        when 'quick' then 'Counted in the P&L, the day book and the journal' || case when g.a_rep then ' and in the expense report.' else '; the expense report leaves it out (the setting "Expense report counts quick expenses" is off).' end
        when 'bank_charge' then 'Only the journal has bank charges: the expense report, the P&L and the day book do not count them.'
        when 'wallet_fee' then case when g.a_pl then 'The P&L and the journal count wallet fees; the expense report and the day book do not.' else 'Not counted: wallet fees are not treated as a separate expense (setting).' end
        else 'Not in the books. No report and no journal counts the marketing register. If the same spend was also typed as an expense voucher it is in the books once, through the voucher.' end,
    'why_bn', case g.class
        when 'voucher_approved' then null
        when 'voucher_submitted' then case when g.a_pl then 'জমা দেওয়া কিন্তু অনুমোদন হয়নি। খরচ রিপোর্ট, P&L ও দিনের খাতা ধরে' else 'জমা দেওয়া কিন্তু অনুমোদন হয়নি। এখনও কোনো মোটে ধরা হয় না (সেটিং শুধু অনুমোদিত ভাউচার ধরে)' end
                                      || case when g.a_jr then ', জার্নালও ধরে।' else '; জার্নাল অনুমোদনের অপেক্ষায়।' end
        when 'voucher_not_counted' then 'খসড়া বা বাতিল: কোনো মোটে ধরা হয় না।'
        when 'voucher_shadow' then 'অন্য পথে এন্ট্রি হওয়া রেকর্ডের কপি: মূল রেকর্ড ধরা হয়, এই কপি নয়।'
        when 'quick' then 'P&L, দিনের খাতা ও জার্নালে ধরা হয়' || case when g.a_rep then ' এবং খরচ রিপোর্টেও।' else '; খরচ রিপোর্ট বাদ দেয় (সেটিং "খরচ রিপোর্টে দ্রুত খরচ ধরো" বন্ধ)।' end
        when 'bank_charge' then 'শুধু জার্নালে ব্যাংক চার্জ আছে: খরচ রিপোর্ট, P&L ও দিনের খাতা ধরে না।'
        when 'wallet_fee' then case when g.a_pl then 'P&L ও জার্নাল ওয়ালেট ফি ধরে; খরচ রিপোর্ট ও দিনের খাতা ধরে না।' else 'ধরা হয় না: ওয়ালেট ফি আলাদা খরচ হিসেবে ধরার সেটিং নেই।' end
        else 'খাতায় নেই। কোনো রিপোর্ট বা জার্নাল মার্কেটিং রেজিস্টার ধরে না। একই খরচ ব্যয় ভাউচারেও লেখা হলে ভাউচার দিয়ে একবার খাতায় আছে।' end)
    order by case g.class when 'voucher_approved' then 1 when 'voucher_submitted' then 2 when 'voucher_not_counted' then 3 when 'voucher_shadow' then 4 when 'quick' then 5 when 'bank_charge' then 6 when 'wallet_fee' then 7 else 8 end), '[]'::jsonb)
    into lines_ from g;

  select coalesce(jsonb_object_agg(l.list_code, l.m), '{}'::jsonb) into labels from (
    select o.list_code, jsonb_object_agg(o.value_code, jsonb_build_object('bn', o.label_bn, 'en', coalesce(o.label_en, o.label_bn))) m
      from public.option_lists o where o.list_code in ('expense_heads', 'marketing_heads') group by o.list_code) l;

  sm_en := 'Expense report ' || public._c1_money((tot ->> 'report')::numeric) || '; P&L ' || public._c1_money((tot ->> 'pl')::numeric)
      || case when (tot ->> 'daybook')::numeric <> (tot ->> 'pl')::numeric then ' (the day book shows ' || public._c1_money((tot ->> 'daybook')::numeric) || ': it leaves out wallet fees)' else ' (the day book shows the same)' end
      || '; journal ' || public._c1_money((tot ->> 'journal')::numeric) || '.'
    || coalesce((select ' ' || string_agg(x ->> 'label_en' || ' ' || public._c1_money((x ->> 'amount')::numeric) || ': ' || (x ->> 'why_en'), ' ' order by ord) from jsonb_array_elements(lines_) with ordinality t(x, ord)
                  where x ->> 'why_en' is not null), '');
  sm_bn := 'খরচ রিপোর্ট ' || public._c1_money((tot ->> 'report')::numeric) || '; P&L ' || public._c1_money((tot ->> 'pl')::numeric)
      || case when (tot ->> 'daybook')::numeric <> (tot ->> 'pl')::numeric then ' (দিনের খাতায় ' || public._c1_money((tot ->> 'daybook')::numeric) || ': ওয়ালেট ফি বাদ)' else ' (দিনের খাতায় একই)' end
      || '; জার্নাল ' || public._c1_money((tot ->> 'journal')::numeric) || '।'
    || coalesce((select ' ' || string_agg(x ->> 'label_bn' || ' ' || public._c1_money((x ->> 'amount')::numeric) || ': ' || (x ->> 'why_bn'), ' ' order by ord) from jsonb_array_elements(lines_) with ordinality t(x, ord)
                  where x ->> 'why_bn' is not null), '');

  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc, 'basis', basis, 'rows', rows_, 'count', cnt, 'shown_amount', shown, 'limit', lim, 'offset', off, 'has_more', (off + lim) < cnt,
    'totals', tot, 'recon', jsonb_build_object('lines', lines_, 'unposted', unp, 'summary_en', sm_en, 'summary_bn', sm_bn,
        'agree', (tot ->> 'report') = (tot ->> 'pl') and (tot ->> 'pl') = (tot ->> 'journal')),
    'labels', labels, 'settings', jsonb_build_object('expense_count_on', cnt_rule, 'report_expense_parity_on', par, 'd_wallet_fee_treatment', wf));
end $$;

revoke all on function public._c1_exp_view(), public._c1_je_live(text, text), public._c1_exp_rows(date, date, int[]) from public, anon, authenticated;
revoke all on function public.expense_register(date, date, int, text, text[], text, int, int) from public, anon;
grant execute on function public.expense_register(date, date, int, text, text[], text, int, int) to authenticated;
notify pgrst, 'reload schema';
