-- Phase 460 (RPT-C3, package R7 part 3) - MARKETING REPORTS #168 #169 #170 #171: coupon / offer usage, customer acquisition cost, repeat purchase after a promotion, marketing ROI.
-- Paste AFTER phase459. Paste-twice safe. Read-only functions. No earlier phase file is edited.
--
--   #168 coupon usage    validated coupons come from the CRM-F tables (crmf_coupons / crmf_coupon_uses) WHEN THEY EXIST - this file creates NO coupon table. Codes typed at the till
--                        without CRM-F (phase458 tags) are shown in a second block labelled "typed, not validated". A sale in both is counted once (as validated).
--   #169 CAC             spend / new customers, ALWAYS with the share of new customers whose source is filled. By-source spend only where the source equals a campaign.
--   #170 repeat          customers who bought on a promotion and bought again within N days after it. N is typed by the person or comes from the setting mkt_repeat_days
--                        (blank = "data needed"; no default is invented). A window that is not over yet is marked incomplete.
--   #171 ROI             ONLY attributable data: tagged sales and campaign-assigned spend. Unassigned spend is shown apart and is NOT in any ROI. Contribution is on the costed part,
--                        with the costed share shown. No ratio is shown when its inputs are missing. Nothing here says a campaign caused a sale.
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.mkt_campaign_performance(date,date,integer)') is null then raise exception 'phase460 needs phase459 first'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'reports', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('mkt_repeat_days', 'number', null::jsonb, 'days', null::jsonb, 1::numeric, 365::numeric,
   'Repeat purchase window after a promotion (days)',
   'The marketing report "repeat purchase after a promotion" counts a customer as a repeat buyer if he buys again within this many days after the promotion ended. Blank = the report asks the person to type the days; nothing is assumed.', 910)
  ) as v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ---------- #168 coupon / offer usage ----------
create or replace function public.mkt_coupon_usage(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; crmf boolean := public._c3_crmf_present(); val jsonb := '[]'; typed jsonb; tot jsonb;
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if crmf then
    execute $q$
      select coalesce(jsonb_agg(jsonb_build_object('code', z.code, 'name', z.name, 'kind', z.kind, 'value', z.value, 'campaign_ref', z.campaign_ref, 'uses', z.uses,
               'customers', z.customers, 'discount_given', z.disc, 'bill_total', z.bt, 'mismatches', z.mism, 'first_use', z.f, 'last_use', z.l) order by z.uses desc, z.code), '[]'::jsonb)
        from (select c.code, c.name, c.kind, c.value, c.campaign_ref, count(*) as uses, count(distinct u.customer_id) as customers, round(sum(u.discount_given), 2) as disc,
                     round(sum(u.bill_total), 2) as bt, count(*) filter (where u.mismatch) as mism, min(s.sale_date) as f, max(s.sale_date) as l
                from public.crmf_coupon_uses u join public.crmf_coupons c on c.id = u.coupon_id join public.sales s on s.id = u.sale_id
               where s.status = 'done' and s.sale_date between $1 and $2 and s.location_id = any ($3) group by 1, 2, 3, 4, 5) z $q$
      into val using p_from, p_to, locs;
    execute $q$
      select coalesce(jsonb_agg(jsonb_build_object('offer_code', z.offer_code, 'bills', z.bills, 'discount_given', z.disc, 'net', z.net, 'campaign_code', z.camp) order by z.bills desc, z.offer_code), '[]'::jsonb)
        from (select t.offer_code, count(*) as bills, round(sum(s.discount), 2) as disc, round(sum(s.total), 2) as net, max(t.campaign_code) as camp
                from public.mkt_sale_tags t join public.sales s on s.id = t.sale_id
               where t.offer_code is not null and s.status = 'done' and s.sale_date between $1 and $2 and s.location_id = any ($3)
                 and not exists (select 1 from public.crmf_coupon_uses u where u.sale_id = t.sale_id) group by 1) z $q$
      into typed using p_from, p_to, locs;
  else
    select coalesce(jsonb_agg(jsonb_build_object('offer_code', z.offer_code, 'bills', z.bills, 'discount_given', z.disc, 'net', z.net, 'campaign_code', z.camp) order by z.bills desc, z.offer_code), '[]'::jsonb)
      into typed
      from (select t.offer_code, count(*) as bills, round(sum(s.discount), 2) as disc, round(sum(s.total), 2) as net, max(t.campaign_code) as camp
              from public.mkt_sale_tags t join public.sales s on s.id = t.sale_id
             where t.offer_code is not null and s.status = 'done' and s.sale_date between p_from and p_to and s.location_id = any (locs) group by 1) z;
  end if;
  tot := jsonb_build_object('validated_uses', coalesce((select sum((x ->> 'uses')::int) from jsonb_array_elements(val) x), 0),
                            'typed_bills', coalesce((select sum((x ->> 'bills')::int) from jsonb_array_elements(typed) x), 0));
  return jsonb_build_object('key', 'mkt_coupons', 'from', p_from, 'to', p_to, 'loc', p_loc, 'crmf_installed', crmf, 'validated', val, 'typed', typed, 'totals', tot,
    'notes', case when crmf then jsonb_build_array('validated_from_crmf', 'typed_codes_not_validated', 'tier_offers_in_customer_tier_report')
                  else jsonb_build_array('crmf_not_installed', 'typed_codes_not_validated', 'tier_offers_in_customer_tier_report') end,
    'basis', case when crmf then 'Validated = coupon uses recorded by the coupon module (CRM-F). Typed = a code written on the bill that matches no recorded coupon use.'
                  else 'The coupon module (CRM-F) is not installed, so no coupon is validated. The codes below were typed on the bill and are not checked against any list.' end);
end $$;

-- ---------- #169 customer acquisition cost ----------
create or replace function public.mkt_cac(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; spend numeric; n_new bigint; n_src bigint; by_src jsonb; attrib_spend numeric; attrib_new bigint; first_loc boolean := p_loc is not null;
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  select sum(l.amt) filter (where l.amt > 0) into spend from public._c3_mkt_lines(p_from, p_to, locs) l;
  with fs as (select s.customer_id, (array_agg(s.location_id order by s.sale_date, s.sold_at))[1] as loc1 from public.sales s where s.status = 'done' and s.customer_id is not null group by 1),
  nc as (select c.id, nullif(btrim(c.source), '') as src from public.customers c left join fs on fs.customer_id = c.id
          where coalesce(c.customer_since, (c.created_at at time zone 'Asia/Dhaka')::date) between p_from and p_to
            and (not first_loc or fs.loc1 = any (locs)))
  select count(*), count(*) filter (where src is not null) into n_new, n_src from nc;
  with fs as (select s.customer_id, (array_agg(s.location_id order by s.sale_date, s.sold_at))[1] as loc1 from public.sales s where s.status = 'done' and s.customer_id is not null group by 1),
  nc as (select c.id, nullif(btrim(c.source), '') as src from public.customers c left join fs on fs.customer_id = c.id
          where coalesce(c.customer_since, (c.created_at at time zone 'Asia/Dhaka')::date) between p_from and p_to
            and (not first_loc or fs.loc1 = any (locs))),
  sp as (select l.campaign_code, sum(l.amt) filter (where l.amt > 0) as spend from public._c3_mkt_lines(p_from, p_to, locs) l where l.campaign_code is not null group by 1),
  cm as (select o.value_code, public._c3_norm(o.label_bn) as nb, public._c3_norm(o.label_en) as ne, public._c3_norm(o.value_code) as nc from public.option_lists o where o.list_code = 'marketing_campaigns'),
  g as (select coalesce(nc.src, '') as src, count(*) as n from nc group by 1),
  j as (select g.src, g.n, (select max(cm.value_code) from cm where g.src <> '' and public._c3_norm(g.src) in (cm.nb, cm.ne, cm.nc)) as camp from g)
  select coalesce(jsonb_agg(jsonb_build_object('source', nullif(j.src, ''), 'new_customers', j.n, 'campaign_code', j.camp, 'campaign_spend', round(sp.spend, 2),
           'cac', case when sp.spend > 0 and j.n > 0 then round(sp.spend / j.n, 2) end) order by (j.src = ''), j.n desc), '[]'::jsonb),
         sum(sp.spend), sum(j.n) filter (where sp.spend is not null)
    into by_src, attrib_spend, attrib_new
    from j left join sp on sp.campaign_code = j.camp;
  return jsonb_build_object('key', 'mkt_cac', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', by_src,
    'totals', jsonb_build_object('marketing_spend', round(spend, 2), 'new_customers', n_new, 'new_with_source', n_src,
       'cac_all', case when spend > 0 and n_new > 0 then round(spend / n_new, 2) end,
       'attributable_spend', round(attrib_spend, 2), 'attributable_new_customers', attrib_new,
       'cac_attributable', case when attrib_spend > 0 and attrib_new > 0 then round(attrib_spend / attrib_new, 2) end),
    'coverage', jsonb_build_object('new_customers', n_new, 'with_source', n_src, 'source_pct', case when n_new > 0 then round(100.0 * n_src / n_new, 1) end),
    'notes', jsonb_build_array('source_coverage_shown', 'cac_all_is_a_blend', 'new_customer_is_date_of_first_record', 'no_causal_claim') ||
             case when first_loc then jsonb_build_array('place_filter_uses_first_sale_place') else '[]'::jsonb end,
    'basis', 'Spend = paid 18-1 lines. New customer = a customer record dated in the period (customer since, else created). CAC (all) = all marketing spend / all new customers. CAC (attributable) = spend of campaigns whose name is a customer source / new customers with those sources.');
end $$;

-- ---------- #170 repeat purchase after a promotion ----------
create or replace function public.mkt_repeat_after_promo(p_campaign text default null, p_days int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d int := coalesce(p_days, public.rule_num('mkt_repeat_days')::int); locs int[]; rows_ jsonb; td date := public._c3_today();
begin
  perform public._c3_need('marketing'); locs := public._c3_locs(null);
  if d is null then return jsonb_build_object('key', 'mkt_repeat', 'data_needed', jsonb_build_array('mkt_repeat_days'), 'rows', '[]'::jsonb,
      'notes', jsonb_build_array('window_days_not_set'), 'basis', 'Type the number of days, or the owner sets "Repeat purchase window after a promotion". No value is assumed.'); end if;
  if d < 1 or d > 365 then raise exception 'bad_days'; end if;
  with camp as (select o.value_code as code, o.label_bn, o.label_en, public._c3_xdate(o.extra, 'start') as st, public._c3_xdate(o.extra, 'end') as en
                  from public.option_lists o where o.list_code = 'marketing_campaigns' and (p_campaign is null or o.value_code = p_campaign)),
  tg as (select c.code, s.id as sale_id, s.customer_id, s.sale_date from camp c
           join public.mkt_sale_tags t on t.campaign_code = c.code join public.sales s on s.id = t.sale_id and s.status = 'done' and s.location_id = any (locs)
         union select c.code, s.id, s.customer_id, s.sale_date from camp c
           join public.mkt_order_tags ot on ot.campaign_code = c.code join public.online_orders oo on oo.id = ot.order_id join public.sales s on s.id = oo.sale_id and s.status = 'done' and s.location_id = any (locs)),
  win as (select c.code, c.label_bn, c.label_en, coalesce(c.en, max(tg.sale_date)) as promo_end, c.st, count(tg.sale_id) as bills,
                 count(tg.sale_id) filter (where tg.customer_id is not null) as bills_known, count(distinct tg.customer_id) as custs
            from camp c left join tg on tg.code = c.code group by c.code, c.label_bn, c.label_en, c.en, c.st having count(tg.sale_id) > 0),
  rep as (select w.code, count(distinct s2.customer_id) as repeaters, min(s2.sale_date - w.promo_end) as first_gap
            from win w join tg on tg.code = w.code and tg.customer_id is not null
            join public.sales s2 on s2.customer_id = tg.customer_id and s2.status = 'done' and s2.location_id = any (locs)
                 and s2.sale_date > w.promo_end and s2.sale_date <= w.promo_end + d
                 and not exists (select 1 from tg x where x.sale_id = s2.id and x.code = w.code)
           group by w.code)
  select coalesce(jsonb_agg(jsonb_build_object('campaign_code', w.code, 'name_bn', w.label_bn, 'name_en', w.label_en, 'promo_end', w.promo_end, 'window_from', w.promo_end + 1, 'window_to', w.promo_end + d,
        'window_complete', w.promo_end + d <= td - 1, 'tagged_bills', w.bills, 'tagged_bills_with_customer', w.bills_known,
        'identified_pct', round(100.0 * w.bills_known / w.bills, 1), 'promo_customers', w.custs, 'repeat_customers', coalesce(r.repeaters, 0),
        'repeat_pct', case when w.custs > 0 and w.promo_end + d <= td - 1 then round(100.0 * coalesce(r.repeaters, 0) / w.custs, 1) end,
        'repeat_pct_so_far', case when w.custs > 0 then round(100.0 * coalesce(r.repeaters, 0) / w.custs, 1) end,
        'end_is_last_tagged_sale', (select c.en is null from camp c where c.code = w.code)) order by w.promo_end desc), '[]'::jsonb)
    into rows_ from win w left join rep r on r.code = w.code;
  return jsonb_build_object('key', 'mkt_repeat', 'window_days', d, 'rows', rows_,
    'notes', jsonb_build_array('only_identified_customers', 'incomplete_window_marked', 'no_causal_claim', 'repeat_means_a_later_bill_not_tagged_to_the_same_campaign'),
    'basis', 'Customers (with a name or mobile on the bill) who bought on a bill tagged to the campaign, and who bought again within ' || d || ' days after the campaign ended (a campaign with no end date uses its last tagged sale).');
end $$;

-- ---------- #171 marketing ROI (attributable data only) ----------
create or replace function public.mkt_roi(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare perf jsonb; locs int[]; unassigned numeric; rows_ jsonb; cost_ok boolean := public.rpt_cost_ok();
begin
  perform public._c3_need('marketing'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  perf := public.mkt_campaign_performance(p_from, p_to, p_loc);
  select sum(l.amt) filter (where l.amt > 0) into unassigned from public._c3_mkt_lines(p_from, p_to, locs) l where l.campaign_code is null;
  select coalesce(jsonb_agg(r || jsonb_build_object(
        'revenue_per_taka', case when (r ->> 'spend')::numeric > 0 and r ->> 'revenue_net' is not null then round((r ->> 'revenue_net')::numeric / (r ->> 'spend')::numeric, 2) end,
        'roi_pct_costed_part', case when cost_ok and (r ->> 'spend')::numeric > 0 and r ->> 'contribution_costed' is not null
              then round(100 * ((r ->> 'contribution_costed')::numeric - (r ->> 'spend')::numeric) / (r ->> 'spend')::numeric, 1) end,
        'why_no_roi', case when r ->> 'spend' is null then 'no_spend_recorded' when (r ->> 'spend')::numeric <= 0 then 'no_spend_recorded'
                           when r ->> 'revenue_net' is null then 'no_tagged_sales' when not cost_ok then 'cost_hidden' when r ->> 'contribution_costed' is null then 'no_costed_sales' end)
        order by (r ->> 'revenue_net')::numeric desc nulls last), '[]'::jsonb)
    into rows_ from jsonb_array_elements(perf -> 'rows') r;
  return jsonb_build_object('key', 'mkt_roi', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'coverage', perf -> 'coverage',
    'unassigned_spend_not_in_roi', round(unassigned, 2),
    'notes', jsonb_build_array('attributable_data_only', 'contribution_on_costed_part', 'unassigned_spend_not_in_roi', 'untagged_sales_not_counted_roi_may_be_understated', 'no_causal_claim') ||
             case when cost_ok then '[]'::jsonb else jsonb_build_array('cost_hidden') end,
    'basis', 'ROI % = (contribution on the costed part - campaign spend) / campaign spend. Revenue per taka = tagged net sales / campaign spend. Only bills that carry the campaign and 18-1 lines assigned to the campaign are used.');
end $$;

revoke all on function public.mkt_coupon_usage(date, date, int), public.mkt_cac(date, date, int), public.mkt_repeat_after_promo(text, int), public.mkt_roi(date, date, int) from public, anon;
grant execute on function public.mkt_coupon_usage(date, date, int), public.mkt_cac(date, date, int), public.mkt_repeat_after_promo(text, int), public.mkt_roi(date, date, int) to authenticated;
notify pgrst, 'reload schema';
