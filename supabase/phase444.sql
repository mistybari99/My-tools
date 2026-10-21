-- Phase 444 (bos444) - STATEMENTS, part 2 (package RPT-C1, block R3): the cash-flow statement and the working capital. Paste AFTER phase443. Paste-twice safe. New objects only.
-- WHY (docs/REPORTS_AUDIT_3.md F12, reports 124 and 126): the Cash flow tab lists movements of the cash accounts by source; an opening journal inside the period shows as a 900,000 inflow, a bank deposit
--      shows as 2,000 in AND 2,000 out, and nothing says operating / investing / financing. There is no working-capital figure.
-- WHAT THIS FILE DOES (read only for the books: no journal line is written)
--   1. Setting report_cf_opening_through (text date, blank): journals dated on or before it are opening balances, not flows. Opening journals (source opening) are ALWAYS opening.
--   2. stmt_cash_flow(from, to, place): cash-flow statement from the journal, DIRECT method. Cash = the same accounts as the Cash flow tab. For every journal entry the cash it moved is shared over the
--      other lines of the entry, and each line goes to the cash-flow class of its chart account (phase 443: operating / investing / financing; blank = "unclassified" - nothing is guessed).
--      Opening journals are left out of the flows (shown on their own line); a move between two cash accounts (deposit, withdrawal, wallet top-up) is netted: it is not a flow.
--      opening + operating + investing + financing + unclassified + opening journals in the period = closing, and the closing is the same figure as the Cash flow tab (the test proves it).
--      stmt_cf_drill(from, to, place, class, account): the journal entries behind one class or account.
--   4. c1_export_log(key, kind, filters, rows): the export gate + audit line for the CSV of the expense register (442) and of these statements (owner or export_data, plus the right to read the screen).
--   3. stmt_working_capital(as_of, place): (a) by the current / non-current class of each asset and liability account (phase 443): current assets - current liabilities, accounts without a class listed apart;
--      (b) the plain formula cash + customer receivables + inventory - supplier payables from the mapped accounts. Without any class (a) says "not captured", it never shows 0.
-- Access: as phase 443 (owner, accounts view / manage, or the report grant of the profit group). Without the accounting start date: "accounting module not switched on - no data captured".

do $g$ begin
  if to_regprocedure('public._c1_p443_present()') is null then raise exception 'phase444 needs phase443 first'; end if;
end $g$;

create or replace function public._c1_p444_present() returns boolean language sql immutable as $$ select true $$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('report_cf_opening_through', 'reports', 'text', null, null, null, null, null,
  'ক্যাশ-ফ্লো স্টেটমেন্ট: এই তারিখ পর্যন্ত জার্নাল শুরুর ব্যালেন্স', 'Cash-flow statement: এই তারিখ পর্যন্ত journal শুরুর balance', 'Cash-flow statement: journals up to this date are opening balances',
  'YYYY-MM-DD লিখুন। শুরুর ব্যালেন্স হাতে জার্নালে (manual) দিলে তার তারিখ এখানে দিন, তাহলে সেটি ক্যাশ-ফ্লো-এর আয় হিসেবে আসবে না। ফাঁকা থাকলে শুধু "শুরুর ব্যালেন্স" ধরনের জার্নাল বাদ যায়।',
  'YYYY-MM-DD লিখুন। শুরুর balance হাতে journal-এ (manual) দিলে তার তারিখ এখানে দিন, তাহলে সেটি cash-flow-এর আয় হিসেবে আসবে না। ফাঁকা থাকলে শুধু "শুরুর ব্যালেন্স" ধরনের journal বাদ যায়।',
  'Type a date as YYYY-MM-DD. If you entered the opening balances as an ordinary manual journal, give its date here so that it is not counted as a cash inflow. Blank: only journals of the kind "opening balances" are left out.', 818)
on conflict (key) do nothing;

create or replace function public._c1_open_through() returns date language plpgsql stable security definer set search_path = public as $$
declare v text := public.rule_txt('report_cf_opening_through');
begin
  if v is null or btrim(v) !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  begin return btrim(v)::date; exception when others then return null; end;
end $$;

-- ---------- 2. cash-flow statement ----------
create or replace function public.stmt_cash_flow(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); to_ date := coalesce(p_to, public._acct_today()); fr date; v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); ids bigint[] := public._c1_cash_ids();
  thr date := public._c1_open_through(); open_ numeric; classes jsonb; srcs jsonb; flows numeric; opening_in numeric; transfers numeric; unalloc numeric; n_transfer bigint; n_manual_open bigint;
  unc_amt numeric; notes_ jsonb := '[]'::jsonb;
begin
  if not public._stmt_view() then raise exception 'not allowed'; end if;
  if st is null then
    return jsonb_build_object('data_needed', true, 'reason', 'accounting_not_started', 'text_en', 'The accounting module is not switched on (no start date) - no data captured.',
      'text_bn', 'হিসাব মডিউল চালু নেই (শুরুর তারিখ নেই) - কোনো তথ্য সংগ্রহ হয়নি।');
  end if;
  fr := coalesce(p_from, st);
  if fr > to_ or to_ - fr > 1100 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(sum(l.debit - l.credit), 0) into open_ from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
   where l.account_id = any (ids) and e.entry_date < fr and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc);

  with en as (
    select e.id, e.entry_date, e.source_type, coalesce(e.subtype, e.source_type) as cat,
           (e.source_type = 'opening' or exists (select 1 from public.journal_entries o where o.id = e.reverses_id and o.source_type = 'opening') or (thr is not null and e.entry_date <= thr)) as is_open,
           coalesce(sum(l.debit) filter (where l.account_id = any (ids)), 0) as cdr, coalesce(sum(l.credit) filter (where l.account_id = any (ids)), 0) as ccr,
           coalesce(sum(l.debit - l.credit) filter (where l.account_id = any (ids)), 0) as cash_net,
           coalesce(sum(l.credit - l.debit) filter (where not (l.account_id = any (ids))), 0) as ab,
           count(*) filter (where not (l.account_id = any (ids))) as n_counter
      from public.journal_entries e join public.journal_lines l on l.entry_id = e.id
     where e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
     group by e.id having bool_or(l.account_id = any (ids))),
  ct as (
    select en.id, l.account_id, coalesce(c.cf_class, 'unclassified') as cls, en.cash_net * (l.credit - l.debit) / en.ab as contrib
      from en join public.journal_lines l on l.entry_id = en.id and not (l.account_id = any (ids)) and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
      left join public.coa_report_class c on c.account_id = l.account_id
     where not en.is_open and en.ab <> 0),
  pa as (select account_id, cls, coalesce(sum(greatest(contrib, 0)), 0) as i, coalesce(sum(greatest(-contrib, 0)), 0) as o from ct group by account_id, cls),
  pc as (select cls, sum(i) i, sum(o) o,
                jsonb_agg(jsonb_build_object('account_id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'in', pa.i, 'out', pa.o, 'net', pa.i - pa.o) order by a.code) accounts
           from pa join public.coa_accounts a on a.id = pa.account_id group by cls),
  cl as (select coalesce(jsonb_agg(jsonb_build_object('class', k.cls, 'in', coalesce(pc.i, 0), 'out', coalesce(pc.o, 0), 'net', coalesce(pc.i, 0) - coalesce(pc.o, 0), 'accounts', coalesce(pc.accounts, '[]'::jsonb)) order by k.ord), '[]'::jsonb) j
           from (values ('operating', 1), ('investing', 2), ('financing', 3), ('unclassified', 4)) k(cls, ord) left join pc on pc.cls = k.cls),
  sr as (select coalesce(jsonb_agg(jsonb_build_object('category', cat, 'in', i, 'out', o, 'net', i - o) order by cat), '[]'::jsonb) j
           from (select cat, coalesce(sum(greatest(cash_net, 0)), 0) i, coalesce(sum(greatest(-cash_net, 0)), 0) o from en where not is_open and (cash_net <> 0) group by cat) z),
  tt as (select coalesce(sum(cash_net) filter (where not is_open), 0) as flows, coalesce(sum(cash_net) filter (where is_open), 0) as opening_in, coalesce(sum(least(cdr, ccr)) filter (where not is_open), 0) as transfers,
                coalesce(sum(cash_net) filter (where not is_open and ab = 0 and cash_net <> 0), 0) as unalloc, count(*) filter (where not is_open and least(cdr, ccr) > 0) as n_transfer,
                count(*) filter (where e2.source_type = 'manual' and e2.entry_date = st and not e2.is_open and thr is null) as n_manual_open
           from en e2)
  select cl.j, sr.j, tt.flows, tt.opening_in, tt.transfers, tt.unalloc, tt.n_transfer, tt.n_manual_open into classes, srcs, flows, opening_in, transfers, unalloc, n_transfer, n_manual_open from cl, sr, tt;

  select ((x ->> 'in')::numeric + (x ->> 'out')::numeric) into unc_amt from jsonb_array_elements(classes) x where x ->> 'class' = 'unclassified';
  if coalesce(unc_amt, 0) > 0 then
    notes_ := notes_ || jsonb_build_array(jsonb_build_object('code', 'unclassified', 'level', 'warn',
      'text_en', 'Some cash movements belong to accounts that have no cash-flow class yet. They are shown as "unclassified" - nothing is guessed. Give the accounts a class in the Classes tab.',
      'text_bn', 'কিছু নগদ লেনদেন এমন অ্যাকাউন্টের যার ক্যাশ-ফ্লো ক্লাস এখনও দেওয়া হয়নি। সেগুলো "অশ্রেণিবদ্ধ" দেখাচ্ছে - কিছু আন্দাজ করা হয়নি। Classes ট্যাবে অ্যাকাউন্টে ক্লাস দিন।'));
  end if;
  if coalesce(unalloc, 0) <> 0 then
    notes_ := notes_ || jsonb_build_array(jsonb_build_object('code', 'unallocated', 'level', 'warn', 'amount', unalloc,
      'text_en', 'Part of the cash movement could not be shared over the other lines of its journal entry (the other lines are in places you cannot see): ' || public._c1_money(unalloc) || '.',
      'text_bn', 'নগদ লেনদেনের একটি অংশ তার জার্নাল এন্ট্রির অন্য লাইনে ভাগ করা যায়নি (অন্য লাইন আপনার দেখার বাইরের জায়গায়): ' || public._c1_money(unalloc) || '।'));
  end if;
  if coalesce(n_manual_open, 0) > 0 then
    notes_ := notes_ || jsonb_build_array(jsonb_build_object('code', 'maybe_opening', 'level', 'warn', 'n', n_manual_open,
      'text_en', n_manual_open || ' manual journal(s) are dated on the accounting start date and move cash. If they are the opening balances, give their date in the setting "journals up to this date are opening balances" - until then they count as cash inflows.',
      'text_bn', n_manual_open || 'টি হাতে-করা জার্নাল হিসাব শুরুর তারিখে এবং নগদ নাড়াচ্ছে। এগুলো শুরুর ব্যালেন্স হলে সেটিং "এই তারিখ পর্যন্ত জার্নাল শুরুর ব্যালেন্স"-এ তারিখ দিন - নইলে এগুলো নগদ আয় হিসেবে ধরা হবে।'));
  end if;
  if coalesce(opening_in, 0) <> 0 then
    notes_ := notes_ || jsonb_build_array(jsonb_build_object('code', 'opening_in_period', 'level', 'info', 'amount', opening_in,
      'text_en', 'Opening balances posted inside this period (' || public._c1_money(opening_in) || ') are not a flow: they are shown on their own line.',
      'text_bn', 'এই সময়ের মধ্যে পোস্ট করা শুরুর ব্যালেন্স (' || public._c1_money(opening_in) || ') কোনো লেনদেন নয়: আলাদা লাইনে দেখানো হয়েছে।'));
  end if;
  return jsonb_build_object('from', fr, 'to', to_, 'location_id', p_loc, 'opening', open_, 'classes', classes, 'by_source', srcs,
    'flows', flows, 'opening_in_period', opening_in, 'transfers_netted', transfers, 'transfer_entries', n_transfer, 'unallocated', unalloc,
    'closing', open_ + flows + opening_in,
    'opening_through', thr,
    'notes', notes_,
    'basis', jsonb_build_object('text_en', 'Direct method from the journal. Cash = the cash, bank and mobile wallet accounts (the same as the Cash flow tab of Accounts). Each cash movement is placed in the class of the other account of its journal entry. A move between two cash accounts is netted.',
      'text_bn', 'জার্নাল থেকে সরাসরি পদ্ধতি। নগদ = ক্যাশ, ব্যাংক ও মোবাইল ওয়ালেট অ্যাকাউন্ট (হিসাবের Cash flow ট্যাবের মতোই)। প্রতিটি নগদ লেনদেন তার জার্নাল এন্ট্রির অন্য অ্যাকাউন্টের ক্লাসে যায়। দুই নগদ অ্যাকাউন্টের মধ্যে স্থানান্তর নেট করা হয়।'));
end $$;

create or replace function public.stmt_cf_drill(p_from date, p_to date, p_loc int, p_class text, p_account bigint default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); ids bigint[] := public._c1_cash_ids(); thr date := public._c1_open_through();
  cls text := lower(coalesce(nullif(btrim(p_class), ''), 'all')); rows_ jsonb;
begin
  if not public._stmt_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 1100 then raise exception 'bad_range'; end if;
  if cls not in ('operating', 'investing', 'financing', 'unclassified', 'opening', 'transfer', 'all') then raise exception 'bad_value'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with en as (
    select e.id, e.entry_date, e.source_type, e.memo,
           (e.source_type = 'opening' or exists (select 1 from public.journal_entries o where o.id = e.reverses_id and o.source_type = 'opening') or (thr is not null and e.entry_date <= thr)) as is_open,
           coalesce(sum(l.debit) filter (where l.account_id = any (ids)), 0) as cdr, coalesce(sum(l.credit) filter (where l.account_id = any (ids)), 0) as ccr,
           coalesce(sum(l.debit - l.credit) filter (where l.account_id = any (ids)), 0) as cash_net,
           coalesce(sum(l.credit - l.debit) filter (where not (l.account_id = any (ids))), 0) as ab
      from public.journal_entries e join public.journal_lines l on l.entry_id = e.id
     where e.entry_date between p_from and p_to and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
     group by e.id having bool_or(l.account_id = any (ids))),
  ct as (
    select en.id, en.entry_date, en.source_type, en.memo, l.account_id, coalesce(c.cf_class, 'unclassified') as k, en.cash_net * (l.credit - l.debit) / en.ab as amt
      from en join public.journal_lines l on l.entry_id = en.id and not (l.account_id = any (ids)) and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
      left join public.coa_report_class c on c.account_id = l.account_id
     where not en.is_open and en.ab <> 0),
  un as (
    select id, entry_date, source_type, memo, null::bigint as account_id, (case when is_open then 'opening' else 'transfer' end) as k, (case when is_open then cash_net else least(cdr, ccr) end) as amt
      from en where is_open or (least(cdr, ccr) > 0)),
  allr as (select * from ct union all select * from un)
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', z.id, 'entry_date', z.entry_date, 'source_type', z.source_type, 'memo', z.memo, 'class', z.k, 'account_id', z.account_id,
           'account_code', a.code, 'amount', z.amt) order by z.entry_date desc, abs(z.amt) desc, z.id), '[]'::jsonb) into rows_
    from (select * from allr where (cls = 'all' or k = cls) and (p_account is null or account_id = p_account) order by entry_date desc, abs(amt) desc limit 300) z left join public.coa_accounts a on a.id = z.account_id;
  return jsonb_build_object('from', p_from, 'to', p_to, 'class', cls, 'account_id', p_account, 'rows', rows_);
end $$;

-- ---------- 3. working capital ----------
create or replace function public.stmt_working_capital(p_as_of date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); as_ date := coalesce(p_as_of, public._acct_today()); ids bigint[] := public._c1_cash_ids(); cash_ numeric; recv numeric; inv numeric; pay numeric;
  ca jsonb; cl jsonb; nca jsonb; ncl jsonb; ua jsonb; ul jsonb; sums jsonb; classed int; notes_ jsonb := '[]'::jsonb; wc numeric; n_un int;
begin
  if not public._stmt_view() then raise exception 'not allowed'; end if;
  if st is null then
    return jsonb_build_object('data_needed', true, 'reason', 'accounting_not_started', 'text_en', 'The accounting module is not switched on (no start date) - no data captured.',
      'text_bn', 'হিসাব মডিউল চালু নেই (শুরুর তারিখ নেই) - কোনো তথ্য সংগ্রহ হয়নি।');
  end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with b as (
    select a.id, a.code, a.name_bn, a.name_en, a.type, c.bs_class, case when a.type = 'asset' then x.open_net + x.dr - x.cr else -(x.open_net + x.dr - x.cr) end as amt
      from public._acct_bal(null, as_, p_loc) x join public.coa_accounts a on a.id = x.account_id left join public.coa_report_class c on c.account_id = a.id
     where not a.is_group and a.type in ('asset', 'liability') and (x.open_net <> 0 or x.dr <> 0 or x.cr <> 0)),
  j as (select type, bs_class, jsonb_agg(jsonb_build_object('account_id', id, 'code', code, 'name_bn', name_bn, 'name_en', name_en, 'amount', amt) order by code) accs, sum(amt) tot, count(*) n from b group by type, bs_class)
  select coalesce((select accs from j where type = 'asset' and bs_class = 'current'), '[]'::jsonb), coalesce((select accs from j where type = 'liability' and bs_class = 'current'), '[]'::jsonb),
         coalesce((select accs from j where type = 'asset' and bs_class = 'non_current'), '[]'::jsonb), coalesce((select accs from j where type = 'liability' and bs_class = 'non_current'), '[]'::jsonb),
         coalesce((select accs from j where type = 'asset' and bs_class is null), '[]'::jsonb), coalesce((select accs from j where type = 'liability' and bs_class is null), '[]'::jsonb),
         jsonb_build_object('current_assets', coalesce((select tot from j where type = 'asset' and bs_class = 'current'), 0), 'current_liabilities', coalesce((select tot from j where type = 'liability' and bs_class = 'current'), 0),
           'non_current_assets', coalesce((select tot from j where type = 'asset' and bs_class = 'non_current'), 0), 'non_current_liabilities', coalesce((select tot from j where type = 'liability' and bs_class = 'non_current'), 0),
           'unclassified_assets', coalesce((select tot from j where type = 'asset' and bs_class is null), 0), 'unclassified_liabilities', coalesce((select tot from j where type = 'liability' and bs_class is null), 0)),
         (select count(*) from b where bs_class = 'current'), (select count(*) from b where bs_class is null)
    into ca, cl, nca, ncl, ua, ul, sums, classed, n_un;
  -- the plain formula
  select coalesce(sum(x.open_net + x.dr - x.cr) filter (where a.id = any (ids)), 0),
         coalesce(sum(x.open_net + x.dr - x.cr) filter (where a.id in (select account_id from public.acct_mappings where key = 'receivable')), 0),
         coalesce(sum(x.open_net + x.dr - x.cr) filter (where a.id in (select account_id from public.acct_mappings where key in ('inv_finished', 'inv_raw', 'inv_pack'))), 0),
         coalesce(-sum(x.open_net + x.dr - x.cr) filter (where a.id in (select account_id from public.acct_mappings where key = 'payable')), 0)
    into cash_, recv, inv, pay from public._acct_bal(null, as_, p_loc) x join public.coa_accounts a on a.id = x.account_id where not a.is_group;
  if classed = 0 then
    wc := null;
    notes_ := notes_ || jsonb_build_array(jsonb_build_object('code', 'no_current_class', 'level', 'warn',
      'text_en', 'No account is classed "current" yet, so working capital by class is not calculated (not captured). Give the accounts a class in the Classes tab. The formula below does not need classes.',
      'text_bn', 'এখনও কোনো অ্যাকাউন্ট "চলতি" ক্লাসে নেই, তাই ক্লাস অনুযায়ী ওয়ার্কিং ক্যাপিটাল হিসাব হয়নি (সংগ্রহ হয়নি)। Classes ট্যাবে অ্যাকাউন্টে ক্লাস দিন। নিচের সূত্রে ক্লাস লাগে না।'));
  else
    wc := (sums ->> 'current_assets')::numeric - (sums ->> 'current_liabilities')::numeric;
    if n_un > 0 then
      notes_ := notes_ || jsonb_build_array(jsonb_build_object('code', 'unclassified_balances', 'level', 'warn', 'n', n_un,
        'text_en', n_un || ' asset or liability account(s) with a balance have no current / non-current class: they are listed apart and are NOT in the working capital above.',
        'text_bn', 'ব্যালেন্স আছে এমন ' || n_un || 'টি সম্পদ বা দায়ের অ্যাকাউন্টে চলতি / অ-চলতি ক্লাস নেই: সেগুলো আলাদা তালিকায়, ওপরের ওয়ার্কিং ক্যাপিটালে ধরা হয়নি।'));
    end if;
  end if;
  return jsonb_build_object('as_of', as_, 'location_id', p_loc,
    'by_class', jsonb_build_object('current_assets', ca, 'current_liabilities', cl, 'non_current_assets', nca, 'non_current_liabilities', ncl, 'unclassified_assets', ua, 'unclassified_liabilities', ul,
        'totals', sums, 'working_capital', wc, 'classed_accounts', classed, 'unclassified_accounts', n_un),
    'formula', jsonb_build_object('cash', cash_, 'receivables', recv, 'inventory', inv, 'payables', pay, 'working_capital', cash_ + recv + inv - pay),
    'notes', notes_,
    'basis', jsonb_build_object('text_en', 'From the journal up to the date. By class: current assets minus current liabilities, as you classed the accounts. Formula: cash, bank and wallets + customer receivables + inventory - supplier payables, from the fixed accounts.',
      'text_bn', 'তারিখ পর্যন্ত জার্নাল থেকে। ক্লাস অনুযায়ী: আপনার দেওয়া ক্লাসে চলতি সম্পদ বিয়োগ চলতি দায়। সূত্র: ক্যাশ, ব্যাংক ও ওয়ালেট + গ্রাহকের পাওনা + মজুত - সরবরাহকারীর দেনা, নির্দিষ্ট অ্যাকাউন্ট থেকে।'));
end $$;

-- ---------- 4. export log for the CSV of the expense register and the statements (same gate as the other exports: the owner or the export_data right, plus the right to read that screen) ----------
create or replace function public.c1_export_log(p_key text, p_kind text, p_filters jsonb default '{}'::jsonb, p_rows int default 0) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or p_key not in ('expense_register', 'stmt_pl_matrix', 'stmt_cash_flow', 'stmt_working_capital', 'coa_classes', 'recipe_cost_gaps') then raise exception 'unknown_report'; end if;
  if p_key = 'expense_register' and not public._c1_exp_view() then raise exception 'not allowed'; end if;
  if p_key in ('stmt_pl_matrix', 'stmt_cash_flow', 'stmt_working_capital', 'coa_classes') and not public._stmt_view() then raise exception 'not allowed'; end if;
  if p_key = 'recipe_cost_gaps' and not (public.is_owner() or public.rpt_grant('view_cost')) then raise exception 'not allowed'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;
revoke all on function public.c1_export_log(text, text, jsonb, int) from public, anon;
grant execute on function public.c1_export_log(text, text, jsonb, int) to authenticated;

revoke all on function public._c1_open_through() from public, anon, authenticated;
revoke all on function public.stmt_cash_flow(date, date, int), public.stmt_cf_drill(date, date, int, text, bigint), public.stmt_working_capital(date, int) from public, anon;
grant execute on function public.stmt_cash_flow(date, date, int), public.stmt_cf_drill(date, date, int, text, bigint), public.stmt_working_capital(date, int) to authenticated;
notify pgrst, 'reload schema';
