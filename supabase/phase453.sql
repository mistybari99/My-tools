-- ============================================================
-- Phase 453 - RPT-C2 / R5 part 1 (report #138 customer credit risk and overdue; the "dues not linked to a customer" notice). READ ONLY apart from the credit-days field.
-- Run AFTER phase 452. New file only. Does not touch the CRM tables (phases 300-340). Paste twice = no error.
--
--   customers.credit_days   (new, blank for everyone) the days a customer may take to pay; set with c2_customer_credit_days_set (owner or grant customer_manage = the right that sets the credit limit).
--   rules  credit_default_days (blank)         terms used for a customer with no credit_days of their own. Blank = such a customer has NO terms: their dues are listed but not called overdue.
--          credit_risk_watch_days (blank)      a customer whose oldest overdue amount is this many days past due or more is "watch".
--          credit_risk_high_days (blank)       ... "high". While either is blank the risk column says "rule not set" - ages and amounts are still shown. Nothing here blocks a sale.
--   c2_credit_risk(as_of, only_overdue, search)   one row per customer who owes: balance (the same figure as the dues list), open items aged oldest-first by the SAME rule customer_dues uses
--          (collections and return credits settle the oldest first, opening dues first), due date = item date + terms, overdue amount, days past due, limit used, advance held, advance already applied.
--   c2_credit_terms_list()                      customers that have terms set (for the editing screen).
--   c2_dues_not_linked_notice()                 amounts the customer dues list cannot show: opening dues entered while open_parties_link is OFF, due on sales that have no customer,
--          and (accounting people only) receivable in the journal with no customer. Each with its count and where to fix it.
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_order_profit(date,date,int)') is null then raise exception 'phase453 needs phase452 pasted first'; end if;
end $guard$;

alter table public.customers add column if not exists credit_days int;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'customers_credit_days_c2_chk') then
    alter table public.customers add constraint customers_credit_days_c2_chk check (credit_days is null or (credit_days >= 0 and credit_days <= 3650));
  end if;
end $$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('credit_default_days', 'customers', 'number', null, 'days', null, 0, 3650, 'যে গ্রাহকের নিজের বাকির দিন নেই তার জন্য ডিফল্ট দিন', 'যে customer-এর নিজের credit day নেই তার default দিন', 'Default credit days for a customer with none of their own',
  'ফাঁকা থাকলে নিজের দিন না থাকা গ্রাহকের বাকিকে মেয়াদোত্তীর্ণ বলা হয় না।', 'Blank = a customer with no days of their own has no terms; their dues are listed but not called overdue.', 520),
 ('credit_risk_watch_days', 'customers', 'number', null, 'days', null, 0, 3650, 'এত দিন মেয়াদ পেরোলে গ্রাহক "নজরে"', 'এত দিন মেয়াদ পেরোলে customer "নজরে"', 'Overdue this many days or more = watch',
  'ফাঁকা থাকলে ঝুঁকির কলামে "নিয়ম বসানো নেই" দেখায়; বাকির বয়স ও টাকা তবুও দেখায়।', 'Blank = the risk column says "rule not set"; ages and amounts are still shown.', 521),
 ('credit_risk_high_days', 'customers', 'number', null, 'days', null, 0, 3650, 'এত দিন মেয়াদ পেরোলে গ্রাহক "উচ্চ ঝুঁকি"', 'এত দিন মেয়াদ পেরোলে customer "high risk"', 'Overdue this many days or more = high risk',
  'ফাঁকা থাকলে ঝুঁকির কলামে "নিয়ম বসানো নেই" দেখায়।', 'Blank = the risk column says "rule not set".', 522)
 on conflict (key) do nothing;

create or replace function public.c2_can_read_customers() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_grant('report_customers') or public.rpt_grant('view_reports') or public.can_do('POS', 'view'));
$$;

create or replace function public._c2_audit(p_action text, p_table text, p_id text, p_detail jsonb) returns void language sql security definer set search_path = public as $$
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail) values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_id, p_detail);
$$;

-- owner or the credit-limit right sets the days; every change is an audit line (the customers audit trigger) plus the reason
create or replace function public.c2_customer_credit_days_set(p_customer uuid, p_days int, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.customers;
begin
  if not public.is_active() or not (public.is_owner() or public.has_grant('customer_manage')) then raise exception 'not allowed'; end if;
  select * into c from public.customers where id = p_customer for update;
  if not found then raise exception 'customer_not_found'; end if;
  if p_days is not null and (p_days < 0 or p_days > 3650) then raise exception 'bad_days'; end if;
  if c.credit_days is not distinct from p_days then return jsonb_build_object('id', c.id, 'credit_days', c.credit_days, 'noop', true); end if;
  if c.credit_days is not null and nullif(btrim(p_reason), '') is null then raise exception 'reason_required'; end if;
  update public.customers set credit_days = p_days where id = c.id;
  perform public._c2_audit('credit_days_set', 'customers', c.id::text, jsonb_build_object('from', c.credit_days, 'to', p_days, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('id', c.id, 'credit_days', p_days);
end $$;

-- #138
create or replace function public.c2_credit_risk(p_as_of date default null, p_only_overdue boolean default false, p_search text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare asof date := coalesce(p_as_of, public._dhaka_today()); def int := public.rule_num('credit_default_days')::int; watch int := public.rule_num('credit_risk_watch_days')::int; hi int := public.rule_num('credit_risk_high_days')::int;
        mob boolean := public.can_do('POS', 'view') or public.rpt_mobile_ok(); rows jsonb; sm jsonb; q text := nullif(lower(btrim(p_search)), '');
begin
  if not public.c2_can_read_customers() then raise exception 'not allowed'; end if;
  if asof > public._dhaka_today() then raise exception 'bad_date'; end if;
  with s as (select x.id, x.customer_id, x.sale_date, x.sold_at, x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) as rem
               from public.sales x where x.status = 'done' and x.customer_id is not null and x.sale_date <= asof),
       items as (select cu.id as cid, 0 as ord, public._w1a_cust_open_date(cu.id) as d, public._w1a_cust_open_date(cu.id)::timestamptz as at, public._w1a_cust_open(cu.id) as amt from public.customers cu where public._w1a_cust_open(cu.id) > 0
                 union all select customer_id, 1, sale_date, sold_at, rem from s where rem > 0),
       coll as (select z.customer_id as cid, sum(z.a) as c from (
                  select customer_id, amount as a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null and (paid_at at time zone 'Asia/Dhaka')::date <= asof
                  union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0 and (created_at at time zone 'Asia/Dhaka')::date <= asof) z group by 1),
       cum as (select i.*, sum(i.amt) over (partition by i.cid order by i.ord, i.at) as cr from items i),
       op as (select m.cid, m.d, least(m.amt, greatest(m.cr - coalesce(cl.c, 0), 0)) as open_amt from cum m left join coll cl on cl.cid = m.cid),
       cust as (select cu.id, cu.name, cu.mobile, cu.credit_limit, cu.credit_days, coalesce(cu.credit_days, def) as terms, case when cu.credit_days is not null then 'customer' when def is not null then 'default' else 'none' end as terms_source
                  from public.customers cu where q is null or lower(cu.name) like '%' || q || '%' or cu.mobile like '%' || q || '%'),
       agg as (select c.*, coalesce(sum(o.open_amt), 0) as balance, min(o.d) filter (where o.open_amt > 0) as oldest,
                      coalesce(sum(o.open_amt) filter (where c.terms is not null and o.d is not null and o.d + c.terms < asof), 0) as overdue,
                      coalesce(sum(o.open_amt) filter (where c.terms is not null and o.d is not null and o.d + c.terms >= asof), 0) as not_due,
                      coalesce(sum(o.open_amt) filter (where o.d is null), 0) as undated,
                      max(asof - (o.d + c.terms)) filter (where c.terms is not null and o.d is not null and o.d + c.terms < asof and o.open_amt > 0) as days_past_due
                 from cust c join op o on o.cid = c.id group by c.id, c.name, c.mobile, c.credit_limit, c.credit_days, c.terms, c.terms_source having coalesce(sum(o.open_amt), 0) > 0),
       adv as (select m.customer_id as cid, sum(case when m.kind = 'cust_advance' then m.amount else 0 end) as held_in, sum(case when m.kind = 'cust_advance_used' then m.amount else 0 end) as used,
                      sum(case when m.kind = 'cust_advance' then m.amount else -m.amount end) as net
                 from public.cash_moves m where m.status = 'done' and m.kind like 'cust_advance%' and m.move_date <= asof group by 1),
       r as (select a.*, ad.net as advance_held, ad.used as advance_applied,
                    case when a.credit_limit is not null and a.credit_limit > 0 then round(100.0 * a.balance / a.credit_limit, 1) end as limit_used_pct,
                    case when a.credit_limit is not null and a.balance > a.credit_limit then true else false end as over_limit,
                    case when a.terms is null then 'no_terms' when a.overdue <= 0 then 'ok' when watch is null or hi is null then 'rule_not_set'
                         when a.days_past_due >= hi then 'high' when a.days_past_due >= watch then 'watch' else 'ok' end as risk
               from agg a left join adv ad on ad.cid = a.id where not p_only_overdue or a.overdue > 0)
  select (select coalesce(jsonb_agg(jsonb_build_object('customer_id', id, 'name', name, 'mobile', case when mob then mobile end, 'balance', balance, 'oldest_open', oldest, 'credit_days', credit_days, 'terms_days', terms, 'terms_source', terms_source,
            'overdue', case when terms is null then null else overdue end, 'not_yet_due', case when terms is null then null else not_due end, 'days_past_due', days_past_due, 'undated', undated,
            'credit_limit', credit_limit, 'limit_used_pct', limit_used_pct, 'over_limit', over_limit, 'advance_held', coalesce(advance_held, 0), 'advance_applied', coalesce(advance_applied, 0), 'risk', risk)
            order by overdue desc, balance desc), '[]'::jsonb) from r),
         (select jsonb_build_object('customers_owing', count(*), 'balance_total', coalesce(sum(balance), 0), 'overdue_total', coalesce(sum(overdue) filter (where terms is not null), 0), 'customers_overdue', count(*) filter (where overdue > 0 and terms is not null),
            'owing_without_terms', count(*) filter (where terms is null), 'balance_without_terms', coalesce(sum(balance) filter (where terms is null), 0), 'over_limit', count(*) filter (where over_limit),
            'watch', count(*) filter (where risk = 'watch'), 'high', count(*) filter (where risk = 'high'), 'rule_not_set', count(*) filter (where risk = 'rule_not_set'),
            'default_days', def, 'watch_days', watch, 'high_days', hi) from r)
    into rows, sm;
  return jsonb_build_object('as_of', asof, 'notes', (case when watch is null or hi is null then '["risk_rule_not_set"]'::jsonb else '[]'::jsonb end) || (case when def is null then '["no_default_terms"]'::jsonb else '[]'::jsonb end)
                                                   || '["same_oldest_first_rule_as_dues_list"]'::jsonb || (case when mob then '[]'::jsonb else '["mobile_hidden"]'::jsonb end), 'summary', sm, 'rows', rows);
end $$;

create or replace function public.c2_credit_terms_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.c2_can_read_customers() then raise exception 'not allowed'; end if;
  return jsonb_build_object('can_edit', public.is_owner() or public.has_grant('customer_manage'), 'default_days', public.rule_num('credit_default_days'), 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('customer_id', c.id, 'name', c.name, 'credit_days', c.credit_days, 'credit_limit', c.credit_limit) order by c.name) from public.customers c where c.credit_days is not null), '[]'::jsonb));
end $$;

-- amounts that no customer line carries
create or replace function public.c2_dues_not_linked_notice() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare items jsonb := '[]'::jsonb; a numeric; n int; ar bigint; acct boolean := public._acct_view() and public._acct_all(); st date;
begin
  if not public.c2_can_read_customers() then raise exception 'not allowed'; end if;
  if not public.rule_on('open_parties_link') then
    select coalesce(sum(opening_balance), 0), count(*) into a, n from public.customers where coalesce(opening_balance, 0) > 0;
    if n > 0 then items := items || jsonb_build_object('code', 'opening_not_counted', 'amount', a, 'count', n, 'fix_route', 'openparties'); end if;
  end if;
  select coalesce(sum(due_amount), 0), count(*) into a, n from public.sales where status = 'done' and customer_id is null and due_amount > 0;
  if n > 0 then items := items || jsonb_build_object('code', 'sales_due_no_customer', 'amount', a, 'count', n, 'fix_route', 'dues'); end if;
  st := public._acct_start();
  if acct and st is not null then
    select account_id into ar from public.acct_mappings where key = 'receivable';
    if ar is not null then
      select coalesce(sum(debit - credit), 0), count(*) into a, n from public.journal_lines where account_id = ar and party_id is null;
      if n > 0 and abs(a) > 0.004 then items := items || jsonb_build_object('code', 'journal_receivable_no_customer', 'amount', a, 'count', n, 'fix_route', 'accounts'); end if;
    end if;
  end if;
  return jsonb_build_object('items', items, 'journal_checked', acct and st is not null, 'open_parties_link_on', public.rule_on('open_parties_link'));
end $$;

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';
