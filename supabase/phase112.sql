-- ============================================================
-- Phase 112 (bos112) - BATCH 1a "profit truth": ONE net-profit figure for the shop P&L and the dashboard tile; returns netted in biz_items; shared bills pro-rated by days.
--   Source: docs/audit2/A3_real_profit.md gaps G1 (one figure), G2 (sheet salary vs payroll app, no double count), G3 (wastage / expiry loss), G4 (card fees),
--   G5 (unknown-cost revenue + provisional flag), G6 (shared bills inside the branch result), G7 (unallocated shared bills visible), G8 (one-day report showed the whole month's bills), G9 (returns in biz_items).
--   Needs phases 72..111 pasted first (guard below). Additive, paste-twice safe. NOTHING changes by default: three new rules, all default off = today's behaviour; three advisor rows recommend on.
--     profit_truth_mode        off | on   on = _r3q_l3_shop_pnl (the shop P&L report) returns the rows of _pnl_truth112 (one figure per place: sales with a known cost - cost of goods - expenses
--                                         - salary (paper sheet 02-2 OR payroll app, never both) - wastage - card fees - fixed cost - attributed shared bills; unallocated bills as their own row)
--                                         and the dashboard tile "Net profit" reads profit_truth112 and shows when the figure is provisional.
--     cost_share_prorate_mode  off | on   on = the cost-bill shares of a month are taken pro rata for the days of the report range (a one-day report shows 1/30 of a monthly bill, not all of it).
--     items_net_of_returns     off | on   on = biz_items (and biz_items_by_category, dashboard top items) subtract returns (revenue, quantity, cost), like the margin report.
--   New functions: _c78_rows112, _pl_extra112, _pnl_truth112 (internal), profit_truth112 (RPC, owner / cost right + accounts view). Re-created: _c78_rows (wrapper), _r3q_l3_shop_pnl, biz_items (tag bos112 kept next to bos72 / bos78 / bos88 / bos14).
--   NOT changed on purpose: acct_income_statement and the journal (the books keep their own definition), partner_calculate (a payout base is never changed silently), the report builder item_sales
--   (separate fact view, see the report), printed forms 05-3 / 05-4 / 10-2 (never auto-changed).
--   Body guard: a live body with a tag this file does not know is never overwritten. Tag: bos112.
-- ============================================================

do $g$ begin perform set_config('phase112.ok', 'off', false); end $g$;
do $g$
declare miss text := '';
begin
  if to_regprocedure('public._c78_rows(date,date)') is null then miss := miss || ' 78'; end if;
  if to_regprocedure('public._p27_pl(date,date,integer[])') is null then miss := miss || ' 72'; end if;
  if to_regprocedure('public._p27_src72(date,date,integer[])') is null then miss := miss || ' 72'; end if;
  if to_regprocedure('public._cogs_lines72(date,date,integer[])') is null then miss := miss || ' 72'; end if;
  if to_regprocedure('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)') is null then miss := miss || ' 89'; end if;
  if to_regprocedure('public.biz_items(date,date,integer)') is null or to_regprocedure('public._rcs88()') is null then miss := miss || ' 88'; end if;
  if to_regclass('public.card_settlements85') is null then miss := miss || ' 85'; end if;
  if to_regclass('public.payroll_payments') is null then miss := miss || ' 50'; end if;
  if to_regclass('public.setup_rec_defs81') is null then miss := miss || ' 81'; end if;
  if not exists (select 1 from public.rules where key = 'card_settle_over_mode') then miss := miss || ' 109'; end if;
  if miss <> '' then
    raise exception 'phase112 needs phases 72..111 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  perform set_config('phase112.ok', 'guard1', false);
end $g$;

-- BODY GUARD: a live body with a tag this file does not know (a newer phase) is never overwritten
do $g$
declare d text; t text[]; r record;
begin
  if current_setting('phase112.ok', true) is distinct from 'guard1' then return; end if;
  for r in select * from (values
    ('public._c78_rows(date,date)', array['bos112']::text[]),
    ('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)', array['bos72', 'bos78', 'bos112']::text[]),
    ('public.biz_items(date,date,integer)', array['bos14', 'bos88', 'bos112']::text[])) v(sig, known)
  loop
    d := pg_get_functiondef(r.sig::regprocedure);
    select array_agg(distinct x[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') x;
    if t is not null and not (t <@ r.known) then
      raise exception 'phase112: % carries tags this file does not know (%); build a newer merge instead of overwriting it', r.sig, t;
    end if;
  end loop;
  perform set_config('phase112.ok', 'on', false);
end $g$;

-- ---------- 1. rules (default off = today) + advisor rows ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('profit_truth_mode', 'reports', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'একটাই সত্যিকারের নিট লাভ (দোকান P&L ও ড্যাশবোর্ড): বন্ধ / চালু', 'একটাই সত্যিকারের Net profit (Shop P&L ও Dashboard): off / on', 'One true net profit (shop P&L and dashboard tile): off or on',
  'বন্ধ = আগের মতো। চালু = দোকান P&L ও ড্যাশবোর্ডের "নিট লাভ" একই হিসাবে চলে: খরচ-জানা বিক্রি - মালের খরচ - খরচ - বেতন (কাগজের শিট অথবা পেরোল অ্যাপ, দুটো একসাথে নয়) - নষ্ট মাল - কার্ড ফি - নির্দিষ্ট খরচ - ভাগ করা বিল। ভাগ না-করা বিল আলাদা সারিতে দেখায়। খরচ-না-জানা বিক্রি আলাদা দেখায় এবং অঙ্কটি "অস্থায়ী" চিহ্নিত হয়।',
  'off = আগের মতো। on = Shop P&L ও Dashboard-এর "Net profit" একই হিসাবে চলে: খরচ-জানা বিক্রি - মালের খরচ - খরচ - বেতন (কাগজের শিট অথবা payroll app, দুটো একসাথে নয়) - নষ্ট মাল - card fee - fixed খরচ - ভাগ করা বিল। ভাগ না-করা বিল আলাদা সারিতে দেখায়। খরচ-না-জানা বিক্রি আলাদা দেখায়, অঙ্কটি "provisional" চিহ্নিত হয়।',
  'off = as before (the shop P&L ignores wastage, card fees, app payroll and shared bills; the dashboard tile shows the books figure). on = the shop P&L and the Net profit tile use ONE figure: sales with a known cost minus cost of goods, expenses, salary (paper sheet OR payroll app, never both), wastage, card fees, fixed cost and attributed shared bills. Unallocated shared bills show as their own row. Sales whose cost is unknown are shown apart and the figure is marked provisional.', 984),
 ('cost_share_prorate_mode', 'reports', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'ভাগ করা মাসিক বিল দিন অনুপাতে: বন্ধ / চালু', 'ভাগ করা মাসিক বিল দিন অনুপাতে: off / on', 'Shared monthly bills pro rata by days: off or on',
  'বন্ধ = আগের মতো (এক দিনের রিপোর্টেও পুরো মাসের বিল দেখায়)। চালু = রিপোর্টের তারিখ-সীমার দিন অনুযায়ী মাসিক বিলের অংশ দেখায় (৩০ দিনের মাসে ১ দিন = ১/৩০)।',
  'off = আগের মতো (এক দিনের report-এও পুরো মাসের bill দেখায়)। on = report-এর তারিখ-সীমার দিন অনুযায়ী মাসিক bill-এর অংশ দেখায় (৩০ দিনের মাসে ১ দিন = ১/৩০)।',
  'off = as before (a one-day report shows the whole month''s bills). on = a monthly bill share is taken for the days of the report range only (1 day of a 30-day month = 1/30). Full-month reports are unchanged.', 985),
 ('items_net_of_returns', 'reports', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'আইটেম রিপোর্টে ফেরত বাদ: বন্ধ / চালু', 'Item report-এ return বাদ: off / on', 'Item reports net of returns: off or on',
  'বন্ধ = আগের মতো (সেরা বিক্রির আইটেম ও ক্যাটাগরি রিপোর্টে ফেরত ধরা হয় না)। চালু = ফেরতের টাকা, পরিমাণ ও খরচ বাদ যায়, যেমন মার্জিন রিপোর্টে। "ফেরত বাদ দিয়ে রিপোর্ট" চালু থাকলে তবেই কাজ করে।',
  'off = আগের মতো (সেরা বিক্রির Item ও Category report-এ return ধরা হয় না)। on = return-এর টাকা, পরিমাণ ও খরচ বাদ যায়, যেমন margin report-এ। "Report net of returns" চালু থাকলে তবেই কাজ করে।',
  'off = as before (top items and category reports ignore returns). on = returned revenue, quantity and cost are subtracted, like the margin report. Works only while the rule "reports net of returns" is on.', 986)
on conflict (key) do nothing;
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('profit_truth_mode', 'profit_truth_mode', '112', 'reports', '"on"', '{}'::text[],
  'আজ চারটি আলাদা "লাভ" আছে এবং একই তথ্যে মেলে না। চালু করলে দোকান P&L ও ড্যাশবোর্ড একই নিট লাভ দেখায়। সিদ্ধান্ত মালিকের।',
  'আজ চারটি আলাদা "profit" আছে এবং একই তথ্যে মেলে না। on করলে Shop P&L ও Dashboard একই Net profit দেখায়। সিদ্ধান্ত owner-এর।',
  'Today four different profit figures exist and they disagree on the same data. With this on, the shop P&L and the dashboard tile show one net profit that includes wastage, card fees, payroll and shared bills, and say when it is provisional. The owner decides.', 360),
 ('cost_share_prorate_mode', 'cost_share_prorate_mode', '112', 'reports', '"on"', '{}'::text[],
  'চালু করলে এক দিনের বা এক সপ্তাহের রিপোর্টে মাসিক বিলের শুধু সেই দিনের অংশ আসে। সিদ্ধান্ত মালিকের।',
  'on করলে এক দিনের বা এক সপ্তাহের report-এ মাসিক bill-এর শুধু সেই দিনের অংশ আসে। সিদ্ধান্ত owner-এর।',
  'With this on, a one-day or one-week report carries only that many days of a monthly shared bill instead of the whole month. Full-month reports do not change. The owner decides.', 361),
 ('items_net_of_returns', 'items_net_of_returns', '112', 'reports', '"on"', '{}'::text[],
  'চালু করলে সেরা বিক্রির আইটেম ও ক্যাটাগরির হিসাবে ফেরত বাদ যায়, ফলে বেশি-ফেরত-হওয়া পণ্য সেরা দেখায় না। সিদ্ধান্ত মালিকের।',
  'on করলে সেরা বিক্রির Item ও Category-র হিসাবে return বাদ যায়, ফলে বেশি-return-হওয়া পণ্য সেরা দেখায় না। সিদ্ধান্ত owner-এর।',
  'With this on, top-item and category figures subtract returns, so a product that is returned a lot no longer ranks first. The owner decides.', 362)
on conflict do nothing;
end if; end $p112$;

-- ---------- 2. shared bills: the same rows as before, optionally pro rata by days ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._c78_rows112(p_from date, p_to date, p_pro boolean)
 RETURNS TABLE(mth date, share_id bigint, bill_id bigint, source_code text, cost_type text, type_bn text, type_en text, share_loc integer, share_dest text, amount numeric, dkind text, dloc integer, via text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos112: the body of _c78_rows (bos78) with one more factor: p_pro = the days of the range inside the month / days of the month (1 for a full month, and for an open range)
  select z.mth, z.share_id, z.bill_id, z.code, z.cost_type, z.tbn, z.ten, z.share_loc, z.share_dest,
         case when p_pro and p_from is not null and p_to is not null
              then round(z.amt * greatest((least(p_to, (z.mth + interval '1 month')::date - 1) - greatest(p_from, z.mth) + 1), 0)::numeric / ((z.mth + interval '1 month')::date - z.mth), 4)
              else z.amt end,
         d.dkind, d.dloc, d.via
    from (
      select (case when b.period_kind = 'month' then b.period_month else (b.period_month + make_interval(months => g))::date end) mth, sh.id share_id, b.id bill_id, s.code, s.cost_type,
             t.label_bn tbn, coalesce(t.label_en, t.label_bn) ten, sh.location_id share_loc, sh.dest share_dest, (case when b.period_kind = 'month' then sh.amount else sh.amount / 12 end) amt
        from public.cost_bill_shares sh join public.cost_source_bills b on b.id = sh.bill_id join public.cost_sources s on s.id = b.source_id join public.cost_source_types t on t.code = s.cost_type
        cross join lateral generate_series(0, case when b.period_kind = 'year' then 11 else 0 end) g
       where sh.active and sh.kind = 'share' and sh.dest in ('showroom', 'admin') and b.status = 'active') z
    cross join lateral public._c78_dest(z.share_id, z.mth) d
   where z.mth between public._m1(coalesce(p_from, date '2000-01-01')) and coalesce(p_to, date '2999-12-31');
$function$
$f$; end if; end $p112$;

do $p112$ begin if current_setting('phase112.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._c78_rows(p_from date, p_to date)
 RETURNS TABLE(mth date, share_id bigint, bill_id bigint, source_code text, cost_type text, type_bn text, type_en text, share_loc integer, share_dest text, amount numeric, dkind text, dloc integer, via text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos112: same rows as before; rule cost_share_prorate_mode = on takes a monthly share pro rata for the days of the range (default off = the whole month, as before)
  select * from public._c78_rows112(p_from, p_to, coalesce(public.rule_txt('cost_share_prorate_mode'), 'off') = 'on');
$function$
$f$; end if; end $p112$;

-- ---------- 3. what the branch P&L never had: wastage, card fees, payroll-app salary, shadow sheets ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._pl_extra112(d1 date, d2 date, locs integer[])
 RETURNS TABLE(o_loc integer, o_wastage numeric, o_wastage_unk integer, o_fees numeric, o_sal_app numeric, o_sal_shadow numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos112. Wastage / expiry loss = stock written off at the real ledger cost (the same query the journal uses for account 5100); card fee = fee of the settlements in the range (as the journal's 5810);
  -- salary of the payroll app = payments (cash basis, like the journal) of runs that are NOT a shadow copy of a paper sheet; sheet salary of a sheet that IS a shadow of an app run is taken out again (it would count twice).
  with w as (
    select x.location_id as loc, sum(c.amt) as amt, count(*) filter (where c.amt is null or c.amt <= 0)::int as unk
    from public.stock_wastage x
    cross join lateral (select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) as amt
                          from public.stock_ledger_eff96 l where l.ref_type = 'wastage' and l.ref_id = x.id::text and l.reason = 'wastage') c
    where (x.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and x.location_id = any (locs) group by 1),
  f as (
    select c.location_id as loc, sum(c.fee) as amt from public.card_settlements85 c
    where c.status = 'done' and c.settle_date between d1 and d2 and c.location_id = any (locs) group by 1),
  pa as (
    select p.location_id as loc, sum(p.amount + r.rec) as amt
    from public.payroll_payments p
    cross join lateral (select case when l.advance_recovery > 0 and l.net > 0 then least(round(l.advance_recovery * p.amount / l.net, 2), l.advance_recovery) else 0 end as rec
                          from public.payroll_lines l where l.id = p.line_id) r
    where p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text) and p.pay_date between d1 and d2 and p.location_id = any (locs) group by 1),
  ss as (
    select e.location_id as loc,
           sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
    where e.form_code = '02-2' and e.status in ('submitted', 'approved') and public.is_shadow('entries', e.id::text)
      and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1),
  k as (select loc from w union select loc from f union select loc from pa union select loc from ss)
  select k.loc, coalesce(w.amt, 0), coalesce(w.unk, 0), coalesce(f.amt, 0), coalesce(pa.amt, 0), coalesce(ss.amt, 0)
  from k left join w on w.loc = k.loc left join f on f.loc = k.loc left join pa on pa.loc = k.loc left join ss on ss.loc = k.loc;
$function$
$f$; end if; end $p112$;

-- ---------- 4. ONE figure per place: the rows of the shop P&L when profit_truth_mode = on ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._pnl_truth112(d1 date, d2 date, locs integer[])
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos112. profit = sales WITH a known cost - cost of goods - expenses - salary - fixed cost - wastage - card fees - attributed shared bills.
  -- Sales whose cost is unknown are NOT counted at cost 0: they are shown as uncosted_rev, and profit_if_uncosted_free is the figure if they really cost nothing.
  with a as (select o_loc, sum(o_net) net, sum(o_costed) costed, sum(o_cogs) cogs, sum(o_exp) ex, sum(o_sal) sal, sum(o_fixed) fx from public._p27_pl(d1, d2, locs) group by o_loc),
  sx as (select o_loc, sum(o_cogs_fallback) fb, sum(o_unknown_rev) unk from public._p27_src72(d1, d2, locs) group by o_loc),
  x as (select * from public._pl_extra112(d1, d2, locs)),
  rws as (select * from public._c78_rows112(d1, d2, true)),
  sh as (select r.dloc as o_loc, round(sum(r.amount), 2) as amt from rws r where r.dkind <> 'unallocated' and r.dloc = any (locs) group by 1),
  k as (select o_loc from a union select o_loc from x union select o_loc from sh),
  b as (
    select k.o_loc, coalesce(a.net, 0) net, coalesce(a.costed, 0) costed, coalesce(a.cogs, 0) cogs, a.ex, a.fx,
           case when a.sal is not null or x.o_sal_app is not null then coalesce(a.sal, 0) - coalesce(x.o_sal_shadow, 0) + coalesce(x.o_sal_app, 0) end as sal,
           coalesce(x.o_sal_app, 0) sal_app, coalesce(x.o_wastage, 0) wst, coalesce(x.o_wastage_unk, 0) wst_unk, coalesce(x.o_fees, 0) fee, coalesce(sh.amt, 0) shr,
           coalesce(sx.fb, 0) fb, coalesce(sx.unk, 0) unk
    from k left join a on a.o_loc = k.o_loc left join x on x.o_loc = k.o_loc left join sh on sh.o_loc = k.o_loc left join sx on sx.o_loc = k.o_loc)
  select jsonb_build_object(
    'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(b.net, 2), 'cogs', round(b.cogs, 2), 'costed_rev', round(b.costed, 2),
    'uncosted_rev', round(greatest(b.net - b.costed, 0), 2),
    'cogs_fallback', b.fb, 'unknown_cost_rev', b.unk,
    'uncosted_pct', case when b.net > 0 then round(100 * greatest(b.net - b.costed, 0) / b.net, 2) end,
    'expenses', round(b.ex, 2), 'salary', round(b.sal, 2), 'salary_app', round(b.sal_app, 2), 'fixed', b.fx,
    'wastage', round(b.wst, 2), 'wastage_unknown_cost', b.wst_unk, 'card_fees', round(b.fee, 2), 'overheads_attributed', round(b.shr, 2),
    'profit', round(b.costed - b.cogs - coalesce(b.ex, 0) - coalesce(b.sal, 0) - coalesce(b.fx, 0) - b.wst - b.fee - b.shr, 2),
    'profit_if_uncosted_free', round(b.net - b.cogs - coalesce(b.ex, 0) - coalesce(b.sal, 0) - coalesce(b.fx, 0) - b.wst - b.fee - b.shr, 2),
    'profit_pct', case when b.costed > 0 then round(100 * (b.costed - b.cogs - coalesce(b.ex, 0) - coalesce(b.sal, 0) - coalesce(b.fx, 0) - b.wst - b.fee - b.shr) / b.costed, 2) end,
    'row_type', 'truth',
    'gaps', nullif(concat_ws(', ', case when b.ex is null then 'expenses' end, case when b.sal is null then 'salary' end, case when b.fx is null then 'fixed' end,
                              case when b.net > b.costed + 0.004 then 'cogs(uncosted)' end, case when b.wst_unk > 0 then 'wastage(cost unknown)' end), ''))
  from b join public.locations l on l.id = b.o_loc
  union all  -- shared bills nobody is charged with (no attribution setting, or the main centre has no place): their own row, so the total is complete
  select jsonb_build_object('location_id', null, 'location_bn', 'ভাগ না-করা শেয়ার্ড খরচ', 'location_en', 'Unallocated shared costs',
    'expenses', round(u.amt, 2), 'unallocated', round(u.amt, 2), 'profit', -round(u.amt, 2), 'row_type', 'unallocated')
  from (select sum(r.amount) amt from rws r where (r.dkind = 'unallocated' or r.dloc is null) and r.share_loc = any (locs)) u
  where u.amt is not null and u.amt > 0;
$function$
$f$; end if; end $p112$;

-- ---------- 5. the shop P&L report: today's rows unless profit_truth_mode = on ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._r3q_l3_shop_pnl(d1 date, d2 date, locs integer[], flt jsonb)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos112: profit_truth_mode = on returns the rows of _pnl_truth112 (ONE figure, shares inside the place); off = the two selects below, exactly as before
  select t from public._pnl_truth112(d1, d2, locs) t where coalesce(public.rule_txt('profit_truth_mode'), 'off') = 'on'
  union all
  select x from (
  with a as (select o_loc, sum(o_net) net, sum(o_costed) costed, sum(o_cogs) cogs, sum(o_exp) ex, sum(o_sal) sal, sum(o_fixed) fx from public._p27_pl(d1, d2, locs) group by o_loc),
  sx as (select o_loc, sum(o_cogs_fallback) fb, sum(o_unknown_rev) unk from public._p27_src72(d1, d2, locs) group by o_loc)  -- bos72
  select jsonb_build_object(
    'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(a.net, 2), 'cogs', round(a.cogs, 2),
    'cogs_fallback', coalesce(sx.fb, 0), 'unknown_cost_rev', coalesce(sx.unk, 0),   -- bos72
    'uncosted_pct', case when a.net > 0 then round(100 * greatest(a.net - a.costed, 0) / a.net, 2) end,
    'expenses', round(a.ex, 2), 'salary', round(a.sal, 2), 'fixed', a.fx,
    'profit', round(a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0), 2),
    'profit_pct', case when a.net > 0 then round(100 * (a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0)) / a.net, 2) end,
    'gaps', nullif(concat_ws(', ', case when a.ex is null then 'expenses' end, case when a.sal is null then 'salary' end, case when a.fx is null then 'fixed' end, case when a.net > 0 and a.costed < a.net then 'cogs(uncosted)' end), '')) as x
  from a join public.locations l on l.id = a.o_loc left join sx on sx.o_loc = a.o_loc
  where coalesce(public.rule_txt('profit_truth_mode'), 'off') <> 'on'
  union all  -- bos78: attributed cost-bill shares as SEPARATE rows (only when the switch is on)
  select jsonb_build_object(
    'location_id', l.id,
    'location_bn', l.name_bn || ' · খরচ ভাগ: ' || z.type_bn || case when z.dkind = 'main_centre' then ' (মূল কেন্দ্র)' else '' end,
    'location_en', coalesce(l.name_en, l.name_bn) || ' · cost share: ' || z.type_en || case when z.dkind = 'main_centre' then ' (main centre)' else '' end,
    'expenses', z.amt, 'profit', -z.amt, 'row_type', 'cost_share', 'cost_type', z.cost_type, 'cost_share_dest', z.dkind)
  from (select r.dloc, r.dkind, r.cost_type, min(r.type_bn) type_bn, min(r.type_en) type_en, round(sum(r.amount), 2) amt
          from public._c78_rows(d1, d2) r where r.dkind <> 'unallocated' and r.dloc = any (locs) group by 1, 2, 3) z
  join public.locations l on l.id = z.dloc
  where public.rule_on('cost_attrib_in_pl') and coalesce(public.rule_txt('profit_truth_mode'), 'off') <> 'on') old;
$function$
$f$; end if; end $p112$;

-- ---------- 6. the RPC: one company figure with its completeness ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.profit_truth112(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare locs int[]; rws jsonb; co jsonb; un numeric := 0; unc numeric := 0; wu int := 0; np numeric := 0; npf numeric := 0; prov boolean; notes jsonb := '[]'::jsonb;
begin   -- bos112
  if not (public.biz_ok() and public.biz_cost_ok() and public._acct_view()) then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));
  select coalesce(jsonb_agg(t), '[]'::jsonb) into rws from public._pnl_truth112(p_from, p_to, locs) t;
  select coalesce(sum((t ->> 'profit')::numeric), 0), coalesce(sum((t ->> 'profit_if_uncosted_free')::numeric), 0), coalesce(sum((t ->> 'uncosted_rev')::numeric), 0),
         coalesce(sum((t ->> 'wastage_unknown_cost')::int), 0), coalesce(sum((t ->> 'unallocated')::numeric), 0)
    into np, npf, unc, wu, un from jsonb_array_elements(rws) t;
  -- the unallocated row has no profit_if_uncosted_free: it costs the same in both figures
  npf := npf + coalesce((select sum((t ->> 'profit')::numeric) from jsonb_array_elements(rws) t where t ->> 'row_type' = 'unallocated'), 0);
  prov := unc > 0.004 or un > 0.004 or wu > 0;
  if unc > 0.004 then notes := notes || jsonb_build_array('uncosted_revenue'); end if;
  if un > 0.004 then notes := notes || jsonb_build_array('unallocated_shared_costs'); end if;
  if wu > 0 then notes := notes || jsonb_build_array('wastage_cost_unknown'); end if;
  co := jsonb_build_object(
    'net_sales', coalesce((select sum((t ->> 'net_sales')::numeric) from jsonb_array_elements(rws) t), 0),
    'costed_rev', coalesce((select sum((t ->> 'costed_rev')::numeric) from jsonb_array_elements(rws) t), 0),
    'cogs', coalesce((select sum((t ->> 'cogs')::numeric) from jsonb_array_elements(rws) t), 0),
    'expenses', coalesce((select sum((t ->> 'expenses')::numeric) from jsonb_array_elements(rws) t where t ->> 'row_type' = 'truth'), 0),
    'salary', coalesce((select sum((t ->> 'salary')::numeric) from jsonb_array_elements(rws) t), 0),
    'fixed', coalesce((select sum((t ->> 'fixed')::numeric) from jsonb_array_elements(rws) t), 0),
    'wastage', coalesce((select sum((t ->> 'wastage')::numeric) from jsonb_array_elements(rws) t), 0),
    'card_fees', coalesce((select sum((t ->> 'card_fees')::numeric) from jsonb_array_elements(rws) t), 0),
    'overheads_attributed', coalesce((select sum((t ->> 'overheads_attributed')::numeric) from jsonb_array_elements(rws) t), 0),
    'unallocated', un, 'uncosted_rev', unc);
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc, 'mode', coalesce(public.rule_txt('profit_truth_mode'), 'off'),
    'company', co || jsonb_build_object('net_profit', round(np, 2), 'net_profit_if_uncosted_free', round(npf, 2)),
    'rows', rws, 'provisional', prov, 'incomplete', notes);
end $function$
$f$; end if; end $p112$;

-- ---------- 7. biz_items: returns netted (rule items_net_of_returns) ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.biz_items(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
 RETURNS TABLE(item_id uuid, code text, name_bn text, name_en text, unit text, qty numeric, revenue numeric, cogs numeric, share_pct numeric, cum_pct numeric, abc text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cost_ok boolean := public.biz_cost_ok(); locs int[]; nr boolean := coalesce(public.rule_txt('items_net_of_returns'), 'off') = 'on';   -- bos88; bos112: returns netted when the rule is on
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));   -- bos88
  return query
  with ok as (
    select * from public.sales x
    where x.status = 'done' and x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and x.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  ln as (
    select case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end iid,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end qty,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then round((e->>'amount')::numeric * (case when o.subtotal > 0 then o.total / o.subtotal else 1 end), 2) end amt
    from ok o, jsonb_array_elements(case when jsonb_typeof(o.lines) = 'array' then o.lines else '[]'::jsonb end) e),
  by_item0 as (select l.iid, sum(l.qty) q, sum(l.amt) r from ln l where l.iid is not null group by 1),
  rtn as (   -- bos112: what came back (revenue with its discount share, quantity), from the same lines the margin report reads
    select h.item_id iid, sum(h.qty) q, round(sum(h.rev), 2) r from public._cogs_lines72(p_from, p_to, locs) h where nr and h.src = 'return' and h.item_id is not null group by 1),
  by_item as (select coalesce(a.iid, b.iid) iid, coalesce(a.q, 0) - coalesce(b.q, 0) q, coalesce(a.r, 0) - coalesce(b.r, 0) r from by_item0 a full join rtn b on b.iid = a.iid),
  tot as (select coalesce(sum(r), 0) t from by_item),
  cg as (   -- bos14: the count_in_business filter on the typed cost now lives in _cogs_lines72 (cst) and _line_cost88 ; bos88: cost of what was sold from the ONE report source (switch report_cost_source); NULL = some quantity has no known cost (never a silent 0)
    select h.item_id as iid, sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as c, sum((case h.src when 'sale' then 1 else -1 end) * h.unk_rev) as u   -- bos112: returns subtracted (only present when the rule is on)
      from public._cogs_lines72(p_from, p_to, locs) h where (h.src = 'sale' or nr) and h.item_id is not null group by 1),
  j as (
    select i.id, i.code, i.name_bn, i.name_en, i.unit, coalesce(b.q, 0) q, coalesce(b.r, 0) r,
           case when not cost_ok then null
                when b.iid is null then (case when exists (select 1 from public._item_cost_eff88() e where e.item_id = i.id) then 0 end)
                when coalesce(g.u, 0) > 0.004 then null
                else g.c end cg
    from public.items i
    left join by_item b on b.iid = i.id left join cg g on g.iid = i.id
    where (i.is_active and i.sellable) or b.iid is not null),
  r as (
    select j.*, case when (select t from tot) > 0 then round(100 * j.r / (select t from tot), 2) else 0 end sp,
           case when (select t from tot) > 0 then round(100 * sum(j.r) over (order by j.r desc, j.code) / (select t from tot), 2) else 0 end cp
    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, round(r.cg, 2), r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end
  from r order by r.r desc, r.code;
end $function$
$f$; end if; end $p112$;

-- ---------- 8. privileges ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then
  revoke all on function public._c78_rows112(date, date, boolean), public._pl_extra112(date, date, integer[]), public._pnl_truth112(date, date, integer[]) from public, anon, authenticated;
  revoke all on function public.profit_truth112(date, date, integer) from public, anon;
  grant execute on function public.profit_truth112(date, date, integer) to authenticated;
end if; end $p112$;
