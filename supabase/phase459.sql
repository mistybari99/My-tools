-- Phase 459 (RPT-C3, package R7 part 2) - MARKETING REPORTS #164 #165 #166 #167: spend by campaign, spend vs sales, campaign revenue and contribution, discount campaign performance.
-- Paste AFTER phase458. Paste-twice safe. Read-only functions (no table is written). No earlier phase file is edited.
--
-- Rules every figure here follows:
--   * a number that was not captured is NULL ("data not captured" on screen), never 0 and never an estimate;
--   * spend = the paid amount of 18-1 lines (submitted + approved sheets, like the hub report E4 / M2). "Value without payment" (samples) is shown apart and never added;
--   * a line belongs to a campaign when it names one from the master list (campaign_id), else when its free-text campaign equals exactly ONE campaign name; otherwise it is "unassigned";
--   * revenue / contribution are for sales that CARRY a campaign tag (phase458). Untagged sales are not guessed into a campaign, so the share of sales with a tag is always shown;
--   * contribution is on the COSTED part of the sales only (items with a cost price), with the costed share shown. Cost needs rpt_cost_ok(); without it the cost columns are NULL;
--   * access: rpt_access('marketing') (owner, report_marketing or view_reports) and the caller's locations (can_loc). Nothing here says one thing caused another.
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._p458_present()') is null then raise exception 'phase459 needs phase458 first'; end if;
end $g$;

-- ---------- the 18-1 lines with their campaign resolved ----------
create or replace function public._c3_mkt_lines(d1 date, d2 date, locs int[], p_status text[] default array['submitted', 'approved'])
returns table (entry_id uuid, serial int, status text, rev_no int, location_id int, line_no int, day date, head text, campaign_txt text, campaign_code text, via text,
               amt numeric, nonpay numeric, source text, receipt text, approved_by text)
language sql stable security definer set search_path = public as $$
  with camps as (select o.value_code, o.label_bn, o.label_en, o.label_mix from public.option_lists o where o.list_code = 'marketing_campaigns'),
  ln as (
    select e.id as eid, e.serial as ser, e.status as st, e.rev_no as rv, e.location_id as loc, x.ord::int as lno,
           coalesce(public._p26_d(x.l ->> 'date'), e.entry_date) as dy,
           case when x.l ->> 'head' like 'other:%' then 'other' else coalesce(nullif(btrim(x.l ->> 'head'), ''), '-') end as hd,
           nullif(btrim(x.l ->> 'campaign'), '') as ctxt, nullif(btrim(x.l ->> 'campaign_id'), '') as cid,
           public._r2_num(x.l -> 'amt') as am, public._r2_num(x.l -> 'nonpay') as np, nullif(btrim(x.l ->> 'source'), '') as src,
           nullif(btrim(x.l ->> 'receipt'), '') as rc, nullif(btrim(x.l ->> 'approved_by'), '') as ap
      from public.entries e
      cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) with ordinality as x(l, ord)
     where e.form_code = '18-1' and e.status = any (p_status) and e.location_id = any (locs))
  select ln.eid, ln.ser, ln.st, ln.rv, ln.loc, ln.lno, ln.dy, ln.hd, ln.ctxt, coalesce(c1.value_code, c2.value_code),
         case when c1.value_code is not null then 'list' when c2.value_code is not null then 'text' end,
         ln.am, ln.np, ln.src, ln.rc, ln.ap
    from ln
    left join camps c1 on c1.value_code = ln.cid
    left join lateral (select max(c.value_code) as value_code from camps c
                        where ln.ctxt is not null and (public._c3_norm(c.label_bn) = public._c3_norm(ln.ctxt) or public._c3_norm(c.label_en) = public._c3_norm(ln.ctxt)
                              or public._c3_norm(c.label_mix) = public._c3_norm(ln.ctxt)) having count(*) = 1) c2 on c1.value_code is null
   where ln.dy between d1 and d2 and (coalesce(ln.am, 0) > 0 or coalesce(ln.np, 0) > 0)
$$;

-- ---------- per-sale money with returns and the costed part (same method as the management P&L, phase27) ----------
create or replace function public._c3_sale_facts(d1 date, d2 date, locs int[])
returns table (sale_id uuid, sale_date date, location_id int, customer_id uuid, subtotal numeric, discount numeric, total numeric, ret numeric, net numeric, costed_net numeric, cogs numeric)
language sql stable security definer set search_path = public as $$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  cst as (select ic.item_id, ic.cost_price from public.item_costs ic join public.items i on i.id = ic.item_id where i.count_in_business and ic.cost_price is not null),
  s as (select x.id, x.sale_date as sd, x.location_id as loc, x.customer_id as cu, x.subtotal as sub, x.discount as dis, x.total as tot, x.lines
          from public.sales x where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)),
  ln as (
    select s.id as sid, (case when s.sub > 0 then s.tot / s.sub else 1 end) as f,
           case when e ->> 'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e ->> 'amount')::numeric end as amt,
           case when e ->> 'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e ->> 'qty')::numeric end as qty,
           case when e ->> 'item_id' ~ '^[0-9a-f-]{36}$' then (e ->> 'item_id')::uuid end as iid
      from s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e),
  ag as (select ln.sid, sum(ln.amt * ln.f) filter (where c.cost_price is not null) as cr, sum(ln.qty * c.cost_price) filter (where c.cost_price is not null) as cg
           from ln left join cst c on c.item_id = ln.iid group by 1),
  rr as (select r.sale_id as sid, r.amount, r.lines from public.sale_returns r join s on s.id = r.sale_id, net_on where net_on.v and r.status = 'done'),
  rt as (select sid, sum(amount) as ra from rr group by 1),
  rl as (
    select rr.sid, c.cost_price,
           case when e ->> 'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e ->> 'amount')::numeric end as amt,
           case when e ->> 'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e ->> 'qty')::numeric end as qty
      from rr cross join lateral jsonb_array_elements(case when jsonb_typeof(rr.lines) = 'array' then rr.lines else '[]'::jsonb end) e
      left join cst c on c.item_id = (case when e ->> 'item_id' ~ '^[0-9a-f-]{36}$' then (e ->> 'item_id')::uuid end)),
  rg as (select sid, sum(amt) filter (where cost_price is not null) as rcr, sum(qty * cost_price) filter (where cost_price is not null) as rcg from rl group by 1)
  select s.id, s.sd, s.loc, s.cu, s.sub, s.dis, s.tot, coalesce(t.ra, 0), s.tot - coalesce(t.ra, 0),
         case when a.cr is null then null else round(a.cr - coalesce(g.rcr, 0), 2) end, case when a.cg is null then null else round(a.cg - coalesce(g.rcg, 0), 2) end
    from s left join rt t on t.sid = s.id left join ag a on a.sid = s.id left join rg g on g.sid = s.id
$$;

-- ---------- #164 marketing spend by campaign and period ----------
create or replace function public.mkt_spend_by_campaign(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rows_ jsonb; bym jsonb; tot jsonb; cov jsonb;
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  with l as (select * from public._c3_mkt_lines(p_from, p_to, locs)),
  g as (select l.campaign_code,
               sum(l.amt) filter (where l.amt > 0) as spend, sum(l.amt) filter (where l.amt > 0 and l.status = 'approved') as spend_approved,
               count(*) filter (where l.amt > 0) as n_lines, sum(l.nonpay) filter (where l.nonpay > 0) as nonpay,
               min(l.day) as first_day, max(l.day) as last_day, count(*) filter (where l.amt > 0 and l.via = 'text') as n_text_match
          from l group by 1),
  hd as (select campaign_code, jsonb_object_agg(head, a) as heads from (select l.campaign_code, l.head, round(sum(l.amt), 2) as a from l where l.amt > 0 group by 1, 2) z group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('campaign_code', g.campaign_code, 'name_bn', o.label_bn, 'name_en', o.label_en,
           'spend', round(g.spend, 2), 'spend_approved', round(g.spend_approved, 2), 'lines', g.n_lines, 'nonpay_value', round(g.nonpay, 2),
           'budget', public._c3_xnum(o.extra, 'budget'),
           'budget_used_pct', case when public._c3_xnum(o.extra, 'budget') > 0 and g.spend is not null then round(100 * g.spend / public._c3_xnum(o.extra, 'budget'), 1) end,
           'start', public._c3_xdate(o.extra, 'start'), 'end', public._c3_xdate(o.extra, 'end'), 'first_day', g.first_day, 'last_day', g.last_day,
           'matched_by_text', g.n_text_match, 'heads', hd.heads) order by (g.campaign_code is null), g.spend desc nulls last), '[]'::jsonb)
    into rows_
    from g left join public.option_lists o on o.list_code = 'marketing_campaigns' and o.value_code = g.campaign_code left join hd on hd.campaign_code is not distinct from g.campaign_code;
  select coalesce(jsonb_agg(jsonb_build_object('month', z.m, 'campaign_code', z.campaign_code, 'spend', z.a) order by z.m, z.campaign_code nulls last), '[]'::jsonb) into bym
    from (select date_trunc('month', l.day)::date as m, l.campaign_code, round(sum(l.amt), 2) as a from public._c3_mkt_lines(p_from, p_to, locs) l where l.amt > 0 group by 1, 2) z;
  select jsonb_build_object('spend', round(sum(l.amt) filter (where l.amt > 0), 2), 'lines', count(*) filter (where l.amt > 0), 'nonpay_value', round(sum(l.nonpay) filter (where l.nonpay > 0), 2)),
         jsonb_build_object('lines', count(*) filter (where l.amt > 0), 'with_campaign', count(*) filter (where l.amt > 0 and l.campaign_code is not null),
           'pct', case when count(*) filter (where l.amt > 0) > 0 then round(100.0 * count(*) filter (where l.amt > 0 and l.campaign_code is not null) / count(*) filter (where l.amt > 0), 1) end,
           'spend_with_campaign_pct', case when sum(l.amt) filter (where l.amt > 0) > 0 then round(100 * coalesce(sum(l.amt) filter (where l.amt > 0 and l.campaign_code is not null), 0) / sum(l.amt) filter (where l.amt > 0), 1) end)
    into tot, cov from public._c3_mkt_lines(p_from, p_to, locs) l;
  return jsonb_build_object('key', 'mkt_spend', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'by_month', bym, 'totals', tot, 'coverage', cov,
    'notes', jsonb_build_array('spend_paid_only', 'nonpay_apart', 'sheets_submitted_and_approved', 'unassigned_is_not_guessed', 'not_in_books_unless_posted'),
    'basis', '18-1 lines, paid amount, sheets submitted or approved, dated by the line date');
end $$;

-- drill-down: the 18-1 lines behind a campaign row (p_campaign '' or '__none' = lines with no campaign)
create or replace function public.mkt_spend_lines(p_from date, p_to date, p_loc int default null, p_campaign text default null, p_limit int default 500) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[];
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  return jsonb_build_object('key', 'mkt_spend_lines', 'rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.day desc, z.serial desc, z.line_no) from (
      select l.entry_id, l.serial, l.status, l.location_id, l.line_no, l.day, l.head, l.campaign_txt, l.campaign_code, l.via, l.amt, l.nonpay, l.source, l.receipt, l.approved_by,
             (select o.label_en from public.option_lists o where o.list_code = 'marketing_heads' and o.value_code = l.head) as head_name,
             coalesce((select true from public.journal_entries je where je.source_type = 'mkt_spend' and je.source_id like l.entry_id::text || ':%:' || l.line_no and je.reverses_id is null
                         and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id) limit 1), false) as in_books
        from public._c3_mkt_lines(p_from, p_to, locs) l
       where (p_campaign is null or (p_campaign in ('', '__none') and l.campaign_code is null) or l.campaign_code = p_campaign)
       order by l.day desc, l.serial desc, l.line_no limit least(greatest(coalesce(p_limit, 500), 1), 2000)) z), '[]'::jsonb));
end $$;

-- ---------- #165 marketing spend vs sales, same day (extends the hub report M2; no causal claim) ----------
create or replace function public.mkt_spend_vs_sales(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rows_ jsonb; sp numeric; sl numeric; tg numeric;
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  select coalesce(jsonb_agg(x order by x ->> 'day', x ->> 'location_bn'), '[]'::jsonb) into rows_ from public._r3q_m2_marketing_vs_sales(p_from, p_to, locs, '{}'::jsonb) x;
  select sum((x ->> 'spend')::numeric), sum((x ->> 'sales_total')::numeric) into sp, sl from jsonb_array_elements(rows_) x;
  select sum(f.net) into tg from public._c3_sale_facts(p_from, p_to, locs) f join public._c3_sale_campaign(p_from, p_to, locs) c on c.sale_id = f.sale_id where c.campaign_code is not null;
  return jsonb_build_object('key', 'mkt_vs_sales', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_,
    'totals', jsonb_build_object('spend', round(sp, 2), 'sales_total', round(sl, 2), 'campaign_tagged_net', round(tg, 2)),
    'notes', jsonb_build_array('no_causal_claim', 'same_day_only', 'sales_gross_of_returns', 'spend_paid_only'),
    'basis', 'Spend of 18-1 lines and bill totals on the same day and place, side by side. It shows what happened together, not what caused what.');
end $$;

-- ---------- #166 campaign revenue and contribution (tagged sales only) ----------
create or replace function public.mkt_campaign_performance(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; cost_ok boolean; rows_ jsonb; tot jsonb; cov jsonb; all_net numeric; tag_net numeric; tag_bills bigint; all_bills bigint;
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  cost_ok := public.rpt_cost_ok();
  with f as (select * from public._c3_sale_facts(p_from, p_to, locs)),
  t as (select c.campaign_code, count(*) as bills, sum(f.net) as net, sum(f.discount) as disc, sum(f.costed_net) as cnet, sum(f.cogs) as cogs, count(distinct f.customer_id) as custs
          from f join public._c3_sale_campaign(p_from, p_to, locs) c on c.sale_id = f.sale_id where c.campaign_code is not null group by 1),
  sp as (select l.campaign_code, sum(l.amt) filter (where l.amt > 0) as spend, count(*) filter (where l.amt > 0) as n from public._c3_mkt_lines(p_from, p_to, locs) l where l.campaign_code is not null group by 1),
  k as (select campaign_code from t union select campaign_code from sp)
  select coalesce(jsonb_agg(jsonb_build_object('campaign_code', k.campaign_code, 'name_bn', o.label_bn, 'name_en', o.label_en,
        'tagged_bills', coalesce(t.bills, 0), 'no_tagged_sales', t.bills is null,
        'revenue_net', round(t.net, 2), 'discount_given', round(t.disc, 2), 'identified_customers', t.custs,
        'costed_net', case when cost_ok then round(t.cnet, 2) end, 'cogs', case when cost_ok then round(t.cogs, 2) end,
        'contribution_costed', case when cost_ok and t.cnet is not null then round(t.cnet - t.cogs, 2) end,
        'cost_coverage_pct', case when cost_ok and t.net > 0 then round(100 * coalesce(t.cnet, 0) / t.net, 1) end,
        'spend', round(sp.spend, 2), 'spend_lines', sp.n,
        'after_spend_costed', case when cost_ok and t.cnet is not null and sp.spend is not null then round(t.cnet - t.cogs - sp.spend, 2) end,
        'start', public._c3_xdate(o.extra, 'start'), 'end', public._c3_xdate(o.extra, 'end')) order by t.net desc nulls last, k.campaign_code), '[]'::jsonb)
    into rows_
    from k left join t on t.campaign_code = k.campaign_code left join sp on sp.campaign_code = k.campaign_code
         left join public.option_lists o on o.list_code = 'marketing_campaigns' and o.value_code = k.campaign_code;
  select sum(f.net), count(*) into all_net, all_bills from public._c3_sale_facts(p_from, p_to, locs) f;
  select sum(f.net), count(*) into tag_net, tag_bills from public._c3_sale_facts(p_from, p_to, locs) f join public._c3_sale_campaign(p_from, p_to, locs) c on c.sale_id = f.sale_id where c.campaign_code is not null;
  cov := jsonb_build_object('bills', all_bills, 'tagged_bills', tag_bills, 'tagged_pct', case when all_bills > 0 then round(100.0 * tag_bills / all_bills, 1) end,
                            'revenue_net', round(all_net, 2), 'tagged_revenue_net', round(tag_net, 2),
                            'tagged_revenue_pct', case when all_net > 0 then round(100 * coalesce(tag_net, 0) / all_net, 1) end);
  tot := jsonb_build_object('revenue_net', round(tag_net, 2), 'cost_hidden', not cost_ok);
  return jsonb_build_object('key', 'mkt_campaign_perf', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'totals', tot, 'coverage', cov,
    'notes', jsonb_build_array('tagged_sales_only', 'contribution_on_costed_part', 'no_causal_claim', 'spend_in_same_period') || case when cost_ok then '[]'::jsonb else jsonb_build_array('cost_hidden') end,
    'basis', 'Net sales (after returns) of bills that carry the campaign. Contribution = sales of items with a cost price minus their cost. Spend = 18-1 lines of the campaign in the same dates.');
end $$;

-- drill-down: the sales behind a campaign row
create or replace function public.mkt_campaign_sales(p_from date, p_to date, p_loc int default null, p_campaign text default null, p_limit int default 500) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; cost_ok boolean;
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc); cost_ok := public.rpt_cost_ok();
  return jsonb_build_object('key', 'mkt_campaign_sales', 'rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.sale_date desc, z.receipt desc) from (
      select f.sale_id, f.sale_date, s.receipt, f.location_id, c.campaign_code, c.offer_code, c.via, f.discount, f.total, f.ret, f.net,
             case when cost_ok then f.costed_net end as costed_net, case when cost_ok then f.cogs end as cogs, cu.name as customer
        from public._c3_sale_facts(p_from, p_to, locs) f
        join public._c3_sale_campaign(p_from, p_to, locs) c on c.sale_id = f.sale_id
        join public.sales s on s.id = f.sale_id left join public.customers cu on cu.id = f.customer_id
       where p_campaign is null or c.campaign_code = p_campaign
       order by f.sale_date desc, s.receipt desc limit least(greatest(coalesce(p_limit, 500), 1), 2000)) z), '[]'::jsonb));
end $$;

-- ---------- #167 discount campaign performance ----------
create or replace function public.mkt_discount_campaigns(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rows_ jsonb; base jsonb;
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  with f as (select * from public._c3_sale_facts(p_from, p_to, locs)),
  c as (select * from public._c3_sale_campaign(p_from, p_to, locs)),
  j as (select f.*, c.campaign_code, c.offer_code from f left join c on c.sale_id = f.sale_id),
  g as (select coalesce(j.campaign_code, '') as camp, count(*) filter (where j.discount > 0) as disc_bills, sum(j.discount) filter (where j.discount > 0) as disc,
               sum(j.subtotal) filter (where j.discount > 0) as gross, sum(j.net) filter (where j.discount > 0) as net,
               count(*) filter (where j.offer_code is not null and j.discount = 0) as code_without_discount
          from j group by 1 having count(*) filter (where j.discount > 0) > 0 or count(*) filter (where j.offer_code is not null) > 0)
  select coalesce(jsonb_agg(jsonb_build_object('campaign_code', nullif(g.camp, ''), 'name_bn', o.label_bn, 'name_en', o.label_en, 'discount_bills', g.disc_bills,
        'discount_total', round(g.disc, 2), 'gross_of_those_bills', round(g.gross, 2), 'net_of_those_bills', round(g.net, 2),
        'discount_pct_of_gross', case when g.gross > 0 then round(100 * g.disc / g.gross, 1) end,
        'avg_bill_net', case when g.disc_bills > 0 then round(g.net / g.disc_bills, 2) end, 'offer_code_without_discount', g.code_without_discount)
        order by (g.camp = ''), g.disc desc nulls last), '[]'::jsonb)
    into rows_ from g left join public.option_lists o on o.list_code = 'marketing_campaigns' and o.value_code = g.camp;
  select jsonb_build_object('bills', count(*) filter (where discount = 0), 'avg_bill_net', case when count(*) filter (where discount = 0) > 0 then round(sum(net) filter (where discount = 0) / count(*) filter (where discount = 0), 2) end)
    into base from public._c3_sale_facts(p_from, p_to, locs);
  return jsonb_build_object('key', 'mkt_discount', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'baseline_no_discount', base,
    'notes', jsonb_build_array('no_causal_claim', 'compare_with_baseline_is_not_proof', 'untagged_discounts_in_blank_row'),
    'basis', 'Bills with a discount grouped by the campaign they carry (blank = no campaign). Baseline = bills in the same dates with no discount. Staff / approver detail: the Discounts report.');
end $$;

revoke all on function public._c3_mkt_lines(date, date, int[], text[]), public._c3_sale_facts(date, date, int[]) from public, anon, authenticated;
revoke all on function public.mkt_spend_by_campaign(date, date, int), public.mkt_spend_lines(date, date, int, text, int), public.mkt_spend_vs_sales(date, date, int),
  public.mkt_campaign_performance(date, date, int), public.mkt_campaign_sales(date, date, int, text, int), public.mkt_discount_campaigns(date, date, int) from public, anon;
grant execute on function public.mkt_spend_by_campaign(date, date, int), public.mkt_spend_lines(date, date, int, text, int), public.mkt_spend_vs_sales(date, date, int),
  public.mkt_campaign_performance(date, date, int), public.mkt_campaign_sales(date, date, int, text, int), public.mkt_discount_campaigns(date, date, int) to authenticated;
notify pgrst, 'reload schema';
