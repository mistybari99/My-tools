-- Phase 547 - DAILY SUMMARY: xc_summary_compose reads job_runs.ok (fix of phase 494).
-- Paste AFTER phase546. Paste-twice safe (create or replace, same signature). Earlier phase files are not edited.
-- Why: phase 494 counted failed jobs with job_runs.status = 'failed', but job_runs (phase 479) has no status column;
--   it has ok (boolean) and finished_at. The query raised 'column "status" does not exist', so the owner's daily summary
--   failed every time it ran (phase494_test line 50).
-- What: the same function text with the failed-job count read as ok is false (a finished run that did not succeed).
-- No new switch; nothing else changes.

CREATE OR REPLACE FUNCTION public.xc_summary_compose(p_date date DEFAULT NULL::date, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d date := coalesce(p_date, public._today()); dig jsonb; sales_t jsonb; sales_y jsonb; sales_w jsonb; cash jsonb; wallets jsonb; wast jsonb;
        cakes int; cake_specs int; open_o int; failed_jobs int := 0; failed_mail int; failed_ifail int; nflag int := 0; attention int; by_loc jsonb := '[]'::jsonb;
        notes jsonb := '[]'::jsonb; coll numeric := 0; outlet_name text; ex_red int; ex_yellow int; appr int; lowc int; expc int; st jsonb; rc jsonb;
begin
  if not public._xc_summary_ok() then raise exception 'not allowed'; end if;
  if d > public._today() or d < public._today() - 400 then raise exception 'bad_date'; end if;
  if p_loc is not null then
    if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
    select name_en into outlet_name from public.locations where id = p_loc;
  end if;
  -- sales: owner = the whole company (daily_digest, same figures as the e-mail digest); outlet = that place only, same definition (net of returns when the setting is on)
  if p_loc is null then
    dig := public.daily_digest(d);
    sales_t := dig -> 'sales' -> 'today'; sales_y := dig -> 'sales' -> 'yesterday'; sales_w := dig -> 'sales' -> 'last_week'; by_loc := dig -> 'sales' -> 'by_location';
  else
    sales_t := public._xc_outlet_day(d, p_loc); sales_y := public._xc_outlet_day(d - 1, p_loc); sales_w := public._xc_outlet_day(d - 7, p_loc);
  end if;
  select jsonb_build_object('short', coalesce(sum(-amount) filter (where amount < 0), 0), 'over', coalesce(sum(amount) filter (where amount > 0), 0), 'count', count(*))
    into cash from public.exceptions where flag_code = 'cash_short_over' and entry_date = d and (p_loc is null or location_id = p_loc);
  select jsonb_build_object('total', coalesce(sum(amount), 0), 'by_wallet', coalesce(jsonb_agg(jsonb_build_object('wallet', w.wallet, 'amount', w.amount) order by w.wallet) filter (where w.wallet is not null), '[]'::jsonb))
    into wallets from (select sp.wallet, sum(sp.amount) as amount from public.sale_payments sp
                        where sp.mode = 'mobile' and not sp.voided and (sp.paid_at at time zone 'Asia/Dhaka')::date = d and (p_loc is null or sp.location_id = p_loc) group by sp.wallet) w;
  select coalesce(sum(amount), 0) into coll from public.sale_payments where kind = 'collection' and not voided and (paid_at at time zone 'Asia/Dhaka')::date = d and (p_loc is null or location_id = p_loc);
  select jsonb_build_object('count', count(*), 'value', coalesce(round(sum(x.qty * coalesce(b.avg_cost, 0)), 2), 0)) into wast
    from public.stock_wastage x left join public.stock_balance b on b.item_id = x.item_id and b.location_id = x.location_id
   where (x.made_at at time zone 'Asia/Dhaka')::date = d and (p_loc is null or x.location_id = p_loc);
  select count(*) into open_o from public.online_orders where status in ('new', 'confirmed', 'packed') and (p_loc is null or location_id = p_loc);
  select count(*) into cakes from public.online_orders o where o.status in ('new', 'confirmed', 'packed') and o.delivery_date = d + 1 and (p_loc is null or o.location_id = p_loc);
  select count(*) into cake_specs from public.online_orders o where o.status in ('new', 'confirmed', 'packed') and o.delivery_date = d + 1 and (p_loc is null or o.location_id = p_loc)
     and exists (select 1 from public.order_cake_specs c where c.order_id = o.id and c.state = 'active');
  -- company-wide sections: only in the owner summary (an outlet recipient does not see other outlets' dues, approvals or failures)
  if p_loc is null then
    ex_red := (dig -> 'exceptions_open' ->> 'red')::int; ex_yellow := (dig -> 'exceptions_open' ->> 'yellow')::int;
    appr := (dig ->> 'approvals_pending')::int; lowc := (dig -> 'stock_alerts' ->> 'low_items')::int; expc := (dig -> 'stock_alerts' ->> 'expiring_batches')::int;
    select count(*) into failed_ifail from public.intake_failures where state = 'failed';
    select count(*) into failed_mail from public.notify_outbox where status = 'failed' and created_at > now() - interval '1 day';
    if to_regclass('public.job_runs') is not null then
      execute $q$select count(*) from public.job_runs where ok is false and finished_at is not null and started_at > now() - interval '1 day'$q$ into failed_jobs;
    end if;
    st := dig -> 'backup';
  end if;
  attention := coalesce(cash ->> 'count', '0')::int + coalesce(appr, 0) + coalesce(lowc, 0) + coalesce(expc, 0) + coalesce(ex_red, 0) + coalesce(failed_ifail, 0)
             + coalesce(failed_mail, 0) + coalesce(failed_jobs, 0) + cakes + coalesce((wast ->> 'count')::int, 0);
  if p_loc is null and (st ->> 'stale')::boolean then attention := attention + 1; end if;
  -- what the summary says about itself (no ML, no probability)
  notes := jsonb_build_array(
    jsonb_build_object('code', 'figures_are_server_totals', 'text_en', 'Every figure is computed on the server for the day shown; nothing is estimated.', 'text_bn', 'সব সংখ্যা সার্ভারে ওই দিনের হিসাব; কোনো অনুমান নেই।'),
    jsonb_build_object('code', 'net_of_returns', 'text_en', case when public.rule_on('reports_net_of_returns') then 'Sales are net of returns.' else 'Sales are gross (returns not deducted; setting off).' end,
                       'text_bn', case when public.rule_on('reports_net_of_returns') then 'বিক্রি ফেরত বাদে (নিট)।' else 'বিক্রি ফেরত না বাদ দিয়ে (সেটিং বন্ধ)।' end));
  if p_loc is not null then
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'outlet_scope', 'text_en', 'Outlet view: company-wide dues, approvals, stock alerts and failures are left out.', 'text_bn', 'শাখার দৃশ্য: কোম্পানি-ব্যাপী বাকি, অনুমোদন, স্টক সতর্কতা ও ব্যর্থতা বাদ।'));
  end if;
  return jsonb_strip_nulls(jsonb_build_object('date', d, 'scope', case when p_loc is null then 'owner' else 'outlet' end, 'location_id', p_loc, 'location_name_en', outlet_name,
    'generated_at', now(),
    'sales', jsonb_build_object('today', sales_t, 'yesterday', sales_y, 'last_week', sales_w,
       'vs_yesterday_pct', case when (sales_y ->> 'net')::numeric > 0 then round(((sales_t ->> 'net')::numeric - (sales_y ->> 'net')::numeric) * 100 / (sales_y ->> 'net')::numeric, 1) end,
       'vs_last_week_pct', case when (sales_w ->> 'net')::numeric > 0 then round(((sales_t ->> 'net')::numeric - (sales_w ->> 'net')::numeric) * 100 / (sales_w ->> 'net')::numeric, 1) end,
       'by_location', by_loc),
    'cash', cash, 'wallet_receipts', wallets, 'collections', coll, 'wastage', wast,
    'orders', jsonb_build_object('open', open_o, 'cakes_due_tomorrow', cakes, 'cake_specs_due_tomorrow', cake_specs),
    'owner_only', case when p_loc is null then jsonb_build_object('dues', dig -> 'dues', 'approvals_waiting', appr, 'low_stock_items', lowc, 'batches_expiring', expc,
        'red_exceptions', ex_red, 'yellow_exceptions', ex_yellow, 'failed_intake', failed_ifail, 'failed_mail', failed_mail, 'failed_jobs', failed_jobs,
        'backup', st, 'day_close', dig -> 'day_close') end,
    'attention_items', attention, 'nothing_to_report', (attention = 0 and coalesce((sales_t ->> 'bills')::int, 0) = 0),
    'notes', notes));
end $function$;
