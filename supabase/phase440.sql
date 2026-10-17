-- Phase 440 (bos440) - REPORT HONESTY, part 1 (package RPT-C1, block R1). Paste AFTER phase99 (the last Wave 1 phase). Paste-twice safe. Earlier phase files are not edited.
-- WHY (docs/REPORTS_AUDIT_3.md F1, F2, F4): the hub report engine turns "not captured" into 0 in its totals, shows a profit number even when expenses, salary or fixed cost were never
--      captured, calls the management profit a plain "Profit & loss" without saying it is not the books' profit, and the sales reports do not say that they are before returns.
-- WHAT THIS FILE DOES (nothing here changes a stored record or a journal; with every setting at its default the ONLY change to an existing figure is that a total of "nothing captured" is
--      empty instead of 0 - proved by tests/sql/c1_before_after.sh)
--   1. report_run3 (engine 3 totals): a total over a column in which NO row has a value is now null ("not captured"), no longer 0. A column with some values still adds them up. (text patch, marker bos440)
--   2. L1 / L3 (profit and loss by month and shop / shop comparison): new key profit_complete on every row; new setting report_profit_blank_on (default OFF = today's profit number):
--      when ON, a profit whose expenses, salary, fixed cost or cost of goods were not captured is null ("not captured") instead of a number that leaves the missing part out.
--      The two reports are renamed "... (management view)". (text patch, marker bos440)
--   3. report_notes(key, filters, columns): ONE read-only function that returns the notices (basis lines) for a hub report: management view with a link to Profit check and the salary / expense /
--      returns basis, what is missing, the returns line for the sales reports, the expense basis. The list of notices per report is the table report_notice_topics; a topic is a function
--      _c1_n_<topic>(key, from, to, places, filters, columns). Phase 441 adds its topics the same way. Nothing in the report engines is called for this: web/reportnotes.js asks for it.
-- NOT DONE here (phase 441): attendance, compliance, RFM, lapsed, cash short. Not touched at all: engine-1 sales functions (another package adds returns columns there).
-- !! Re-pasting phase 24 or 27 or 72 or 78 or 79 removes the bos440 patches: paste this file again.

do $g$ begin
  if to_regprocedure('public._i1_apply_hooks()') is null then raise exception 'phase440 needs phase99 (and 8 to 98) first'; end if;
  if to_regprocedure('public.report_run3(text,jsonb,text,text,integer)') is null or to_regclass('public.report_defs3') is null
     or to_regprocedure('public._p27_pl(date,date,integer[])') is null or to_regprocedure('public._w1d_view()') is null then
    raise exception 'phase440 needs the report engine and the profit functions of phases 24, 27 and 92';
  end if;
end $g$;

create or replace function public._c1_p440_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic exact-text patch (the phase92 _w1d_patch idea with this package's markers bos440 .. bos449 (a letter after the number tells two patches of one function apart)). A missing or doubled site STOPS the paste; the marker makes the second paste a no-op ----------
create or replace function public._c1_patch(p_fn regprocedure, p_marker text, p_pairs text[]) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int; n int;
begin
  if p_marker is null or p_marker !~ '^bos44[0-9][a-z]?$' then raise exception 'bad_marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    n := (length(def) - length(replace(def, p_pairs[i], ''))) / length(p_pairs[i]);
    if n = 0 then raise exception '% patch site not found in %: %', p_marker, p_fn::text, left(p_pairs[i], 90); end if;
    if n > 1 then raise exception '% patch site is not unique in %: %', p_marker, p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception '% patch of % carries no marker', p_marker, p_fn::text; end if;
  execute def;
  return true;
end $$;
-- the same, for a longer piece: replaces the text from p_start up to (not including) p_end by p_new. Both anchors must exist once, in this order.
create or replace function public._c1_patch_span(p_fn regprocedure, p_marker text, p_start text, p_end text, p_new text) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); a int; b int;
begin
  if p_marker is null or p_marker !~ '^bos44[0-9][a-z]?$' then raise exception 'bad_marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  a := position(p_start in def);
  if a = 0 then raise exception '% patch start not found in %: %', p_marker, p_fn::text, left(p_start, 90); end if;
  if position(p_start in substr(def, a + 1)) > 0 then raise exception '% patch start is not unique in %: %', p_marker, p_fn::text, left(p_start, 90); end if;
  b := position(p_end in substr(def, a + length(p_start)));
  if b = 0 then raise exception '% patch end not found in %: %', p_marker, p_fn::text, left(p_end, 90); end if;
  b := a + length(p_start) + b - 1;
  def := substr(def, 1, a - 1) || p_new || substr(def, b);
  if position(p_marker in def) = 0 then raise exception '% patch of % carries no marker', p_marker, p_fn::text; end if;
  execute def;
  return true;
end $$;
revoke all on function public._c1_patch(regprocedure, text, text[]), public._c1_patch_span(regprocedure, text, text, text, text) from public, anon, authenticated;

-- ---------- setting (rules, module reports). Default OFF = today's profit number. ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('report_profit_blank_on', 'reports', 'switch', 'false', null, null, null, null,
  'লাভ-ক্ষতি রিপোর্টে তথ্য না থাকলে "সংগ্রহ হয়নি" দেখাও', 'Profit report-এ তথ্য না থাকলে "not captured" দেখাও', 'Profit shows "not captured" when a part of it is missing',
  'বন্ধ থাকলে লাভের সংখ্যা আগের মতোই থাকে (যে অংশের তথ্য নেই সেটি বাদ দিয়ে)। চালু করলে খরচ, বেতন, স্থির খরচ বা মালের খরচের তথ্য না থাকা সারিতে লাভের ঘরে "সংগ্রহ হয়নি" দেখায়।',
  'Off রাখলে profit-এর সংখ্যা আগের মতোই থাকে (যে অংশের data নেই সেটি বাদ দিয়ে)। On করলে খরচ, বেতন, স্থির খরচ বা মালের খরচের data না থাকা row-এ profit ঘরে "not captured" দেখায়।',
  'Off keeps the profit number exactly as it is today (it leaves the missing part out). On shows "not captured" instead of a profit on every row where expenses, salary, fixed cost or cost of goods were not captured.', 810)
on conflict (key) do nothing;

-- ---------- 1. engine 3 totals: nothing captured is null, never 0 ----------
select public._c1_patch('public.report_run3(text,jsonb,text,text,integer)'::regprocedure, 'bos440', array[
  $o$targs := targs || format('%L, round(coalesce(sum((r ->> %L)::numeric), 0), 4), ', k, k);$o$,
  $n$targs := targs || format('%L, case when count(r ->> %L) = 0 then null else round(sum((r ->> %L)::numeric), 4) end, ', k, k, k);   /* bos440: a column with no value at all is "not captured" (null), not 0 */$n$]);

-- ---------- 2. L1 / L3: profit_complete on every row, profit blank when asked and a part is missing ----------
select public._c1_patch('public._r3q_l1_pnl(date,date,integer[],jsonb)'::regprocedure, 'bos440', array[
  $o$'profit', round(p.o_net - p.o_cogs - coalesce(p.o_exp, 0) - coalesce(p.o_sal, 0) - coalesce(p.o_fixed, 0), 2),$o$,
  $n$'profit', case when public.rule_on('report_profit_blank_on') /* bos440 */ and (p.o_exp is null or p.o_sal is null or p.o_fixed is null or (p.o_net > 0 and p.o_costed < p.o_net)) then null
                    else round(p.o_net - p.o_cogs - coalesce(p.o_exp, 0) - coalesce(p.o_sal, 0) - coalesce(p.o_fixed, 0), 2) end,
    'profit_complete', not (p.o_exp is null or p.o_sal is null or p.o_fixed is null or (p.o_net > 0 and p.o_costed < p.o_net)),$n$]);
select public._c1_patch('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)'::regprocedure, 'bos440', array[
  $o$'profit', round(a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0), 2),$o$,
  $n$'profit', case when public.rule_on('report_profit_blank_on') /* bos440 */ and (a.ex is null or a.sal is null or a.fx is null or (a.net > 0 and a.costed < a.net)) then null
                    else round(a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0), 2) end,
    'profit_complete', not (a.ex is null or a.sal is null or a.fx is null or (a.net > 0 and a.costed < a.net)),$n$,
  $o$'profit_pct', case when a.net > 0 then round(100 * (a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0)) / a.net, 2) end,$o$,
  $n$'profit_pct', case when a.net > 0 and not (public.rule_on('report_profit_blank_on') and (a.ex is null or a.sal is null or a.fx is null or a.costed < a.net)) then round(100 * (a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0)) / a.net, 2) end,$n$]);

-- the two P&L reports say what they are
update public.report_defs3
   set name_en = name_en || ' (management view)', name_bn = name_bn || ' (ম্যানেজমেন্ট ভিউ)', name_mix = coalesce(name_mix, name_bn) || ' (management view)'
 where key in ('l1_pnl', 'l3_shop_pnl') and name_en not like '%(management view)%';

-- ---------- 3. notices (basis lines) for hub reports ----------
create table if not exists public.report_notice_topics (
  report_key text not null,
  topic text not null check (topic ~ '^[a-z0-9_]{1,40}$'),
  sort int not null default 100,
  primary key (report_key, topic)
);
alter table public.report_notice_topics enable row level security;
revoke all on public.report_notice_topics from public, anon, authenticated;

create or replace function public._c1_money(p numeric) returns text language sql immutable set search_path = public as $$
  select case when p is null then '-' else to_char(round(p, 2), 'FM999,999,999,990.00') end $$;

-- the period of a hub report, worked out as the report engines do (preset, or from / to, or this month so far). d1 is null when the preset is unknown.
create or replace function public._c1_period(p_flt jsonb, out d1 date, out d2 date) language plpgsql stable security definer set search_path = public as $$
declare flt jsonb := case when p_flt is not null and jsonb_typeof(p_flt) = 'object' then p_flt else '{}'::jsonb end; today date := (now() at time zone 'Asia/Dhaka')::date; pr jsonb; preset text;
begin
  preset := flt ->> 'preset';
  if preset is not null then
    pr := public.report_presets() -> preset;
    if pr is null or jsonb_typeof(pr) = 'null' then return; end if;
    d1 := (pr ->> 'from')::date; d2 := (pr ->> 'to')::date; return;
  end if;
  d1 := public.rpt_date(flt ->> 'from'); d2 := public.rpt_date(flt ->> 'to');
  if d1 is null and d2 is null then d1 := date_trunc('month', today)::date; d2 := today;
  elsif d1 is null then d1 := d2; elsif d2 is null then d2 := today; end if;
end $$;

-- may this person open this report? true / false; null = no such report (the three report engines are asked in turn)
create or replace function public._c1_report_ok(p_key text) returns boolean language plpgsql stable security definer set search_path = public as $$
declare d public.report_defs3; g jsonb;
begin
  if not public.is_active() then return false; end if;
  g := public.rpt_def(p_key);
  if g is not null then return public.rpt_access(g ->> 'group'); end if;
  if public._r2_def(p_key) is not null then return public._r2_ok(p_key); end if;
  select * into d from public.report_defs3 where key = p_key and is_active;
  if found then return public._r3_ok(d); end if;
  return null;
end $$;

-- topic: management_view. The P&L reports are the management view (daily records), not the books.
create or replace function public._c1_n_mgmt_view(p_key text, d1 date, d2 date, eff int[], flt jsonb, cols text[]) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare src text := coalesce(public.rule_txt('report_salary_source'), 'legacy'); acc boolean := public.rule_on('payroll_accrual_on'); net boolean := coalesce(public.rule_on('reports_net_of_returns'), true);
  one boolean := public.rule_on('profit_one_number_on'); cnt text := coalesce(public.rule_txt('expense_count_on'), 'as_today'); wf text := coalesce(public.rule_txt('d_wallet_fee_treatment'), 'separate_expense');
  b jsonb := '[]'::jsonb; ve text; vb text;
begin
  -- salary
  if src = 'app_first' then
    b := b || jsonb_build_object('code', 'salary', 'text_en', 'Salary: from the payroll runs that are counted; the salary sheet (02-2) is used only for months and places that have no counted run.',
      'text_bn', 'বেতন: গণনায় ধরা পে-রোল রান থেকে; যে মাস বা জায়গায় রান নেই সেখানে শুধু বেতন শিট (০২-২)।');
  elsif acc then
    b := b || jsonb_build_object('code', 'salary', 'text_en', 'Salary: salary sheets (02-2) that are not copies of an app payroll run, plus approved or paid payroll runs (payroll accrual is on).',
      'text_bn', 'বেতন: অ্যাপের পে-রোল রানের কপি নয় এমন বেতন শিট (০২-২) এবং অনুমোদিত বা পরিশোধিত পে-রোল রান (পে-রোল অ্যাক্রুয়াল চালু)।');
  else
    b := b || jsonb_build_object('code', 'salary', 'text_en', 'Salary: taken from the salary sheets (02-2). A payroll run paid in the app is not used here, so this can differ from the money actually paid.',
      'text_bn', 'বেতন: বেতন শিট (০২-২) থেকে। অ্যাপে পরিশোধ করা পে-রোল রান এখানে ধরা হয় না, তাই আসলে দেওয়া টাকার সাথে ভিন্ন হতে পারে।');
  end if;
  -- expenses
  ve := case cnt when 'approved' then 'approved' when 'submitted' then 'submitted or approved' else 'submitted or approved' end;
  vb := case cnt when 'approved' then 'অনুমোদিত' else 'জমা দেওয়া বা অনুমোদিত' end;
  b := b || jsonb_build_object('code', 'expenses',
    'text_en', 'Expenses: expense vouchers (10-2) that are ' || ve || ', plus quick expenses' || case when wf = 'separate_expense' then ' and wallet fees' else '' end || '. '
               || case when one then 'Wasted stock, stock count shortage, goods lost in transit, cash short and running costs paid by supplier bill are counted as the Profit check settings say.'
                       else 'Wasted stock, stock count shortage, goods lost in transit, cash short and running costs paid by supplier bill are NOT in this profit (they are in the journal).' end,
    'text_bn', 'খরচ: ' || vb || ' ব্যয় ভাউচার (১০-২), সাথে দ্রুত খরচ' || case when wf = 'separate_expense' then ' ও ওয়ালেট ফি' else '' end || '। '
               || case when one then 'নষ্ট মাল, গণনায় কম, পথে হারানো মাল, ক্যাশ কম ও সাপ্লায়ার বিলে দেওয়া চলতি খরচ Profit check-এর সেটিং অনুযায়ী ধরা হয়।'
                       else 'নষ্ট মাল, গণনায় কম, পথে হারানো মাল, ক্যাশ কম ও সাপ্লায়ার বিলে দেওয়া চলতি খরচ এই লাভে নেই (এগুলো খাতায় আছে)।' end);
  -- returns
  b := b || jsonb_build_object('code', 'returns', 'text_en', case when net then 'Sales are net of sale returns.' else 'Sale returns are NOT taken off the sales (the returns setting is off).' end,
    'text_bn', case when net then 'বিক্রি থেকে বিক্রি-ফেরত বাদ দেওয়া হয়েছে।' else 'বিক্রি থেকে বিক্রি-ফেরত বাদ দেওয়া হয়নি (ফেরতের সেটিং বন্ধ)।' end);
  return jsonb_build_array(jsonb_build_object('code', 'management_view', 'level', 'info',
    'text_en', 'Management view, not the books. Profit here = net sales - cost of goods - expenses - salary - fixed cost, worked out from the daily records. The journal profit can differ. Profit check shows the difference line by line.',
    'text_bn', 'ম্যানেজমেন্ট ভিউ, হিসাবের খাতা নয়। এখানে লাভ = নিট বিক্রি - মালের খরচ - খরচ - বেতন - স্থির খরচ, দৈনিক রেকর্ড থেকে। খাতার (জার্নাল) লাভ ভিন্ন হতে পারে। Profit check পার্থক্য লাইন ধরে দেখায়।',
    'link', jsonb_build_object('route', 'profitcheck', 'label_en', 'Open Profit check', 'label_bn', 'Profit check খুলুন'), 'basis', b));
end $$;

-- topic: profit_gaps. Which parts were not captured (per month and place for L1, per place for the others).
create or replace function public._c1_n_profit_gaps(p_key text, d1 date, d2 date, eff int[], flt jsonb, cols text[]) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare n int; ne int; ns int; nf int; nc int; nany int; blank boolean := public.rule_on('report_profit_blank_on'); parts_en text[] := '{}'; parts_bn text[] := '{}'; en text; bn text; lv text := 'warn';
begin
  if p_key = 'l1_pnl' then
    select count(*), count(*) filter (where o_exp is null), count(*) filter (where o_sal is null), count(*) filter (where o_fixed is null), count(*) filter (where o_net > 0 and o_costed < o_net),
           count(*) filter (where o_exp is null or o_sal is null or o_fixed is null or (o_net > 0 and o_costed < o_net))
      into n, ne, ns, nf, nc, nany from public._p27_pl(d1, d2, eff);
  else
    select count(*), count(*) filter (where ex is null), count(*) filter (where sal is null), count(*) filter (where fx is null), count(*) filter (where net > 0 and costed < net),
           count(*) filter (where ex is null or sal is null or fx is null or (net > 0 and costed < net))
      into n, ne, ns, nf, nc, nany
      from (select o_loc, sum(o_net) net, sum(o_costed) costed, sum(o_exp) ex, sum(o_sal) sal, sum(o_fixed) fx from public._p27_pl(d1, d2, eff) group by o_loc) z;
  end if;
  if n = 0 then return '[]'::jsonb; end if;
  if p_key = 'l5_breakeven' then
    if nf = 0 then return '[]'::jsonb; end if;
    return jsonb_build_array(jsonb_build_object('code', 'fixed_cost_missing', 'level', 'warn', 'data', jsonb_build_object('places', nf, 'of', n),
      'text_en', 'Fixed cost per month is not set for ' || nf || ' of ' || n || ' place(s): break-even is not calculated for them and shows "not captured". The totals leave them out.',
      'text_bn', n || 'টির মধ্যে ' || nf || 'টি জায়গার মাসিক স্থির খরচ দেওয়া নেই: সেগুলোর ব্রেক-ইভেন হিসাব হয়নি, "সংগ্রহ হয়নি" দেখাচ্ছে। মোটে এগুলো নেই।'));
  elsif p_key = 't4_staff_cost_ratio' then
    if ns = 0 then return '[]'::jsonb; end if;
    return jsonb_build_array(jsonb_build_object('code', 'salary_missing', 'level', 'warn', 'data', jsonb_build_object('places', ns, 'of', n),
      'text_en', 'Salary is not captured for ' || ns || ' of ' || n || ' place(s): their ratio shows "not captured". The totals leave them out.',
      'text_bn', n || 'টির মধ্যে ' || ns || 'টি জায়গার বেতনের তথ্য নেই: সেগুলোর অনুপাত "সংগ্রহ হয়নি" দেখাচ্ছে। মোটে এগুলো নেই।'));
  end if;
  if nany = 0 then return '[]'::jsonb; end if;
  if ne > 0 then parts_en := parts_en || (ne || ' without expenses'); parts_bn := parts_bn || (ne || 'টিতে খরচ নেই'); end if;
  if ns > 0 then parts_en := parts_en || (ns || ' without salary'); parts_bn := parts_bn || (ns || 'টিতে বেতন নেই'); end if;
  if nf > 0 then parts_en := parts_en || (nf || ' without fixed cost'); parts_bn := parts_bn || (nf || 'টিতে স্থির খরচ নেই'); end if;
  if nc > 0 then parts_en := parts_en || (nc || ' with sales that have no known cost'); parts_bn := parts_bn || (nc || 'টিতে খরচ অজানা বিক্রি আছে'); end if;
  en := nany || ' of ' || n || ' row(s) are incomplete: ' || array_to_string(parts_en, ', ') || '. '
        || case when blank then 'The setting "Profit shows not captured..." is ON, so their profit shows "not captured".' else 'Their profit leaves the missing part out. Switch on "Profit shows not captured..." in the settings to show "not captured" there instead.' end;
  bn := n || 'টি সারির মধ্যে ' || nany || 'টি অসম্পূর্ণ: ' || array_to_string(parts_bn, ', ') || '। '
        || case when blank then 'সেটিং "তথ্য না থাকলে সংগ্রহ হয়নি দেখাও" চালু, তাই এগুলোর লাভে "সংগ্রহ হয়নি" দেখাচ্ছে।' else 'এগুলোর লাভে না থাকা অংশ বাদ গেছে। সেখানে "সংগ্রহ হয়নি" দেখাতে সেটিং "তথ্য না থাকলে সংগ্রহ হয়নি দেখাও" চালু করুন।' end;
  return jsonb_build_array(jsonb_build_object('code', 'profit_incomplete', 'level', lv, 'data', jsonb_build_object('rows', n, 'incomplete', nany, 'no_expenses', ne, 'no_salary', ns, 'no_fixed', nf, 'uncosted', nc, 'blank_on', blank),
    'text_en', en, 'text_bn', bn));
end $$;

-- topic: returns_line. The hub sales reports count sales before sale returns: say so and show the returns of the same period and places.
create or replace function public._c1_n_returns_line(p_key text, d1 date, d2 date, eff int[], flt jsonb, cols text[]) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare n int; amt numeric; shown boolean := coalesce(cols && array['returns', 'return_amount', 'returns_amount', 'returns_total', 'net_after_returns'], false); narrow boolean; en text; bn text;
begin
  select count(*), coalesce(sum(r.amount), 0) into n, amt from public.sale_returns r
   where r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (eff);
  narrow := flt ?| array['items', 'categories', 'customer', 'staff', 'modes', 'sale_type'];
  if n = 0 then
    en := 'No sale return was recorded in this period and these places.'; bn := 'এই সময়ে ও এই জায়গাগুলোতে কোনো বিক্রি-ফেরত নেই।';
  else
    en := 'Sale returns in this period: ' || n || ' return(s), ' || public._c1_money(amt) || '. '
          || case when shown then 'They are also in the returns column of this report.' else 'The figures in this report are before returns: take the returns off to get sales after returns.' end;
    bn := 'এই সময়ের বিক্রি-ফেরত: ' || n || 'টি, ৳ ' || public._c1_money(amt) || '। '
          || case when shown then 'রিপোর্টের ফেরতের কলামেও আছে।' else 'এই রিপোর্টের সংখ্যা ফেরতের আগের: ফেরত বাদ দিলে ফেরতের পরের বিক্রি পাবেন।' end;
  end if;
  if narrow then
    en := en || ' The returns line is not narrowed by the item, customer, staff or payment filters.';
    bn := bn || ' আইটেম, গ্রাহক, স্টাফ বা পেমেন্টের ফিল্টারে ফেরতের লাইন ছোট হয় না।';
  end if;
  return jsonb_build_array(jsonb_build_object('code', 'returns_line', 'level', 'info', 'data', jsonb_build_object('count', n, 'amount', amt, 'in_report', shown),
    'text_en', en, 'text_bn', bn, 'link', jsonb_build_object('route', 'salereturn', 'label_en', 'Sale returns', 'label_bn', 'বিক্রি ফেরত')));
end $$;

-- topic: expense_basis. Three expense totals exist for the same period; say which one this report is and where the whole list is.
create or replace function public._c1_n_expense_basis(p_key text, d1 date, d2 date, eff int[], flt jsonb, cols text[]) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare par boolean := public.rule_on('report_expense_parity_on'); cnt text := coalesce(public.rule_txt('expense_count_on'), 'as_today'); en text; bn text;
begin
  if p_key = 'expense_by_head' then
    en := 'This report counts expense vouchers (10-2) that are ' || case cnt when 'approved' then 'approved' else 'submitted or approved' end || '. Quick expenses are '
          || case when par then 'counted (setting on)' else 'NOT counted (setting off)' end || '. Bank charges, wallet fees and marketing (18-1) are not counted.';
    bn := 'এই রিপোর্টে ' || case cnt when 'approved' then 'অনুমোদিত' else 'জমা দেওয়া বা অনুমোদিত' end || ' ব্যয় ভাউচার (১০-২) ধরা হয়। দ্রুত খরচ '
          || case when par then 'ধরা হয় (সেটিং চালু)' else 'ধরা হয় না (সেটিং বন্ধ)' end || '। ব্যাংক চার্জ, ওয়ালেট ফি ও মার্কেটিং (১৮-১) ধরা হয় না।';
  elsif p_key = 'e3_weak_control' then
    en := 'This control report checks expense vouchers (10-2)' || case when par then ' and quick expenses (setting on).' else '; quick expenses are not in it (setting off).' end;
    bn := 'এই কন্ট্রোল রিপোর্ট ব্যয় ভাউচার (১০-২) দেখে' || case when par then ' ও দ্রুত খরচ (সেটিং চালু)।' else '; দ্রুত খরচ এতে নেই (সেটিং বন্ধ)।' end;
  else
    en := 'This trend counts expense vouchers (10-2) and quick expenses, the same as the profit report. The expense report and the journal can show other totals.';
    bn := 'এই ধারায় ব্যয় ভাউচার (১০-২) ও দ্রুত খরচ ধরা হয়, লাভের রিপোর্টের মতোই। খরচ রিপোর্ট ও জার্নালের মোট ভিন্ন হতে পারে।';
  end if;
  return jsonb_build_array(jsonb_build_object('code', 'expense_basis', 'level', 'info', 'text_en', en || ' The Expense register lists every voucher and shows why the totals differ.',
    'text_bn', bn || ' খরচ রেজিস্টার প্রতিটি ভাউচার দেখায় এবং মোট কেন ভিন্ন তা বলে।',
    'link', jsonb_build_object('route', 'expenseregister', 'label_en', 'Open the Expense register', 'label_bn', 'খরচ রেজিস্টার খুলুন')));
end $$;

insert into public.report_notice_topics (report_key, topic, sort) values
 ('l1_pnl', 'mgmt_view', 10), ('l3_shop_pnl', 'mgmt_view', 10), ('l4_owner_sheet', 'mgmt_view', 10), ('l5_breakeven', 'mgmt_view', 10), ('t4_staff_cost_ratio', 'mgmt_view', 10),
 ('l1_pnl', 'profit_gaps', 20), ('l3_shop_pnl', 'profit_gaps', 20), ('l5_breakeven', 'profit_gaps', 20), ('t4_staff_cost_ratio', 'profit_gaps', 20),
 ('sales_summary', 'returns_line', 10), ('sales_trend', 'returns_line', 10), ('sales_combined', 'returns_line', 10), ('item_sales', 'returns_line', 10), ('category_sales', 'returns_line', 10),
 ('hour_weekday', 'returns_line', 10), ('retail_wholesale', 'returns_line', 10), ('receipt_register', 'returns_line', 10),
 ('expense_by_head', 'expense_basis', 10), ('e2_expense_trend', 'expense_basis', 10), ('e3_weak_control', 'expense_basis', 10)
on conflict do nothing;

-- the one function the browser calls. Read only. Same right as the report itself. Reports without a topic answer [].
create or replace function public.report_notes(p_key text, p_filters jsonb default '{}'::jsonb, p_cols text[] default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ok boolean; t record; p record; eff int[]; flt jsonb; out_ jsonb := '[]'::jsonb; r jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  ok := public._c1_report_ok(p_key);
  if ok is null then raise exception 'unknown_report'; end if;
  if not ok then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.report_notice_topics where report_key = p_key) then return out_; end if;
  flt := case when p_filters is not null and jsonb_typeof(p_filters) = 'object' then p_filters else '{}'::jsonb end;
  select * into p from public._c1_period(flt);
  if p.d1 is null then return out_; end if;
  eff := public._r2_locs(flt);
  for t in select topic from public.report_notice_topics where report_key = p_key order by sort, topic loop
    if to_regprocedure('public._c1_n_' || t.topic || '(text,date,date,integer[],jsonb,text[])') is null then continue; end if;
    execute format('select public._c1_n_%s($1, $2, $3, $4, $5, $6)', t.topic) into r using p_key, p.d1, p.d2, eff, flt, p_cols;
    if r is not null and jsonb_typeof(r) = 'array' then out_ := out_ || r; end if;
  end loop;
  return out_;
end $$;

-- closed to browsers: everything with an underscore; open: report_notes (signed in, same right as the report)
revoke all on function public._c1_money(numeric), public._c1_period(jsonb), public._c1_report_ok(text),
  public._c1_n_mgmt_view(text, date, date, integer[], jsonb, text[]), public._c1_n_profit_gaps(text, date, date, integer[], jsonb, text[]),
  public._c1_n_returns_line(text, date, date, integer[], jsonb, text[]), public._c1_n_expense_basis(text, date, date, integer[], jsonb, text[]) from public, anon, authenticated;
revoke all on function public.report_notes(text, jsonb, text[]) from public, anon;
grant execute on function public.report_notes(text, jsonb, text[]) to authenticated;
notify pgrst, 'reload schema';
