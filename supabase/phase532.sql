-- Phase 532 (UNION-4: customer balance, dues, books documents, day book and profit reports carry both lines). Paste-twice safe. Earlier phase files are not edited.
-- What: _cust_bal and customer_dues: opening dues of the open parties package (bos88) and the business scope of the advanced line (scope133, phase 123 org_scope_on) and the customer
--   mobile mask (bos105); customer_dues also keeps our "net of the advance used" clause (phase 503, rule dues_net_advance_on, superseded by the advanced customer_dues_net113 but kept, OFF).
--   _acct_docs: the sources of our phases 81-83, 87, 96 AND the advanced inline sources (stock moves, transit loss, purchase variance, card settlement, landed cost, drawer cash short, bos113).
--   _daybook_lines: money account of an expense voucher (bos87) or its pay mode (bos113, rule daybook_align_mode) and the advanced card-fee and drawer rows.
--   _p27_pl: our payroll accrual and app payroll run (bos85/86/93) and the advanced labour already absorbed into product cost (bos117, rule factory_labour_absorbed117).
--   _r3q_l3_shop_pnl: our blank-profit rule (bos440) inside the advanced profit_truth_mode wrapper (bos112).
-- Every switch involved keeps its own default. Paste AFTER phase531 and after phase 505. Same behaviour on a re-paste as phase530.

create table if not exists public._union_fn_backup (id bigserial primary key, fn text not null, saved_at timestamptz not null default now(), why text, def text not null);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

drop table if exists _u_plan;
create temp table _u_plan (seq serial primary key, fn text not null, kind text not null, a text not null, b text);
-- _cust_bal(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public._cust_bal(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._cust_bal(p_customer uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public._w1a_cust_open(p_customer) /* bos88: opening due */ + coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done' and ((select not public._org_on123()) or public._cfgvis133(s.location_id))),   /* scope133: a customer balance counts the sales of the caller's businesses (owner, server and the notify bot: all) */ 0)
       - coalesce((select sum(p.amount) from public.sale_payments p where p.customer_id = p_customer and not p.voided and ((select not public._org_on123()) or public._cfgvis133(p.location_id))), 0)
       - coalesce((select sum(r.credit_amount) from public.sale_returns r where r.customer_id = p_customer and r.status = 'done' and ((select not public._org_on123()) or public._cfgvis133(r.location_id))), 0);
$function$$r0_0$, null),
  ('public._cust_bal(uuid)', 'known', '316a2ab793e14c118f0cdd8f7dc24fe2', null),
  ('public._cust_bal(uuid)', 'known', '7233c24399dd3254a265c055fc170827', null),
  ('public._cust_bal(uuid)', 'known', 'b9ddd93fb0b5436b0d1ad8b46144e117', null),
  ('public._cust_bal(uuid)', 'old', $o0_0$AS $function$
  select public._w1a_cust_open(p_customer) /* bos88: opening due */ + coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)
       - coalesce((select sum(p.amount) from public.sale_payments p where p.customer_id = p_customer and not p.voided), 0)
       - coalesce((select sum(r.credit_amount) from public.sale_returns r where r.customer_id = p_customer and r.status = 'done'), 0);
$function$$o0_0$, $n0_0$AS $function$
  select public._w1a_cust_open(p_customer) /* bos88: opening due */ + coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done' and ((select not public._org_on123()) or public._cfgvis133(s.location_id))),   /* scope133: a customer balance counts the sales of the caller's businesses (owner, server and the notify bot: all) */ 0)
       - coalesce((select sum(p.amount) from public.sale_payments p where p.customer_id = p_customer and not p.voided and ((select not public._org_on123()) or public._cfgvis133(p.location_id))), 0)
       - coalesce((select sum(r.credit_amount) from public.sale_returns r where r.customer_id = p_customer and r.status = 'done' and ((select not public._org_on123()) or public._cfgvis133(r.location_id))), 0);
$function$$n0_0$);
-- customer_dues()
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_dues()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_dues()
 RETURNS TABLE(id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with s as (
    select x.id, x.customer_id, x.sale_date, x.sold_at,
           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null and (not (select public._org_on123()) or public.can_loc(x.location_id))),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select z.customer_id, sum(z.a) coll from (
          select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null and (not (select public._org_on123()) or public.can_loc(location_id))
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0 and (not (select public._org_on123()) or public.can_loc(location_id))
          union all select customer_id, amount from public.cash_moves where kind = 'cust_advance_used' and status = 'done' and customer_id is not null and public.rule_on('dues_net_advance_on')) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, public._cust_pii103('mobile', cu.mobile) /* bos105 */, cu.type, cu.credit_limit, coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) /* bos88 */ - coalesce(c.coll, 0),
         (case when public._w1a_cust_open(cu.id) > coalesce(c.coll, 0) then public._w1a_cust_open_date(cu.id)
              else (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr + public._w1a_cust_open(cu.id) > coalesce(c.coll, 0)) end)
  from public.customers cu left join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
  where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) and coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) - coalesce(c.coll, 0) > 0
  order by 6 desc;
$function$$r0_0$, null),
  ('public.customer_dues()', 'known', '37acd7f15fb9795a3af819ef50cfc2b4', null),
  ('public.customer_dues()', 'known', '6216d60b85dbb7168e9aa93272bd3873', null),
  ('public.customer_dues()', 'known', '842f16bd58318a3424c7f31defc95a5b', null),
  ('public.customer_dues()', 'known', 'a86ed505fbdcc4245cf4006feed04380', null),
  ('public.customer_dues()', 'old', $o0_0$           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select z.customer_id, sum(z.a) coll from (
          select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0
          union all select customer_id, amount from public.cash_moves where kind = 'cust_advance_used' and status = 'done' and customer_id is not null and public.rule_on('dues_net_advance_on')) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) /* bos88 */ - coalesce(c.coll, 0),
         (case when public._w1a_cust_open(cu.id) > coalesce(c.coll, 0) then public._w1a_cust_open_date(cu.id)$o0_0$, $n0_0$           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null and (not (select public._org_on123()) or public.can_loc(x.location_id))),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select z.customer_id, sum(z.a) coll from (
          select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null and (not (select public._org_on123()) or public.can_loc(location_id))
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0 and (not (select public._org_on123()) or public.can_loc(location_id))
          union all select customer_id, amount from public.cash_moves where kind = 'cust_advance_used' and status = 'done' and customer_id is not null and public.rule_on('dues_net_advance_on')) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, public._cust_pii103('mobile', cu.mobile) /* bos105 */, cu.type, cu.credit_limit, coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) /* bos88 */ - coalesce(c.coll, 0),
         (case when public._w1a_cust_open(cu.id) > coalesce(c.coll, 0) then public._w1a_cust_open_date(cu.id)$n0_0$);
-- _acct_docs(date)
insert into _u_plan (fn, kind, a, b) values
  ('public._acct_docs(date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos97: phase515 body + two landed-cost blocks at the end (landed_cost, landed_cost_void)
-- bos103: production run whose ingredients are all free-cost = known cost 0 (posts conversion only, or nothing when there is none); production-in without recipe via _acct_stock_moves85
-- bos98: merged by phase524 = phase515 body + every bos96 line (stock_ledger_eff96 reads) + both bos97 blocks, so neither phase522 nor phase523 can erase the other
-- bos89: merge of phase506 (free-cost) and phase511 (stock moves, card, voucher mode) bodies; every bos50/52/72/74/80/85 line kept
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
    null::text,
    case when s.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', public._m_key(p.money_account_id, 'pay_' || p.mode) /* bos97 */, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode, p.money_account_id
        union all select 2, jsonb_build_object('a', 'receivable', 'd', round(s.total - pp.paid, 2), 'pt', case when s.customer_id is not null then 'customer' end, 'pid', s.customer_id::text) where s.total - pp.paid > 0.004
        union all select 3, jsonb_build_object('a', 'sales_discount', 'd', s.discount) where s.discount > 0
        union all select 4, jsonb_build_object('a', 'sales', 'c', s.subtotal)
        union all select 5, jsonb_build_object('a', 'cogs', 'd', cg.amt) from (select round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null) cg where cg.amt > 0
        union all select 6, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt) from public._acct_inv_split72(array['sale', 'sale_pack'], s.id::text, array['sale_out', 'issue_out'], -1) z where z.amt > 0 /* bos72: rounding remainder on the largest part */
      ) x) end
  from public.sales s cross join lateral (select coalesce(sum(p.amount), 0) paid from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided) pp
  where s.sale_date >= p_start and s.subtotal > 0 and public._acct_need('sale', s.id::text, s.status = 'done');

  -- sale returns
  return query
  select 'sale_return'::text, r.id::text, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, ('Return of receipt ' || coalesce(s.receipt::text, '-'))::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when r.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
    null::text,
    case when r.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'sales_returns', 'd', r.amount) j
        union all select 2, jsonb_build_object('a', 'receivable', 'c', r.credit_amount, 'pt', case when r.customer_id is not null then 'customer' end, 'pid', r.customer_id::text) where r.credit_amount > 0
        union all select 3, jsonb_build_object('a', public._m_key(r.money_account_id, public._acct_paykey(coalesce(r.refund_mode, 'cash'))), 'c', r.refund_amount) /* bos87 */ where r.refund_amount > 0
        union all select 4, jsonb_build_object('a', public._acct_inv_key(z.t), 'd', z.amt) from public._acct_inv_split72(array['sale_return'], r.id::text, array['sale_return'], 1) z where z.amt > 0 /* bos72 */
        union all select 5, jsonb_build_object('a', 'cogs', 'c', cg.amt) from (select round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null) cg where cg.amt > 0
      ) x) end
  from public.sale_returns r left join public.sales s on s.id = r.sale_id
  where (r.created_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('sale_return', r.id::text, r.status = 'done');

  -- customer collections (later payments of dues)
  return query
  select 'collection'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Due collection'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._m_key(p.money_account_id, public._acct_paykey(p.mode)) /* bos97 */, 'd', p.amount),
      jsonb_build_object('a', 'receivable', 'c', p.amount, 'pt', case when p.customer_id is not null then 'customer' end, 'pid', p.customer_id::text)) end
  from public.sale_payments p
  where p.kind = 'collection' and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('collection', p.id::text, not p.voided);

  -- purchase bills and purchase returns
  return query
  select 'purchase'::text, b.id::text, b.bill_date, b.location_id, ((case b.kind when 'return' then 'Purchase return ' else 'Purchase bill ' end) || coalesce(b.bill_no, '-'))::text, b.kind, b.status = 'posted' and b.total > 0, (b.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when b.status = 'posted' and b.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'payable', case when b.kind = 'return' then 'd' else 'c' end, b.total, 'pt', 'supplier', 'pid', b.supplier_id::text) j
        union all select 2, jsonb_build_object('a', al.k, case when b.kind = 'return' then 'c' else 'd' end, al.amt) from public._acct_purchase_alloc(b.id) al
      ) x) end
  from public.purchase_bills b
  where b.bill_date >= p_start and public._acct_need('purchase', b.id::text, b.status = 'posted' and b.total > 0);

  -- supplier payments
  return query
  select 'supplier_payment'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Supplier payment'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', 'payable', 'd', p.amount, 'pt', 'supplier', 'pid', p.supplier_id::text),
      jsonb_build_object('a', public._m_key(p.money_account_id, public._acct_paykey(p.mode, true)), 'c', p.amount) /* bos87 */) end
  from public.supplier_payments p
  where (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_payment', p.id::text, not p.voided);

  -- supplier refunds
  return query
  select 'supplier_refund'::text, f.id::text, (f.refunded_at at time zone 'Asia/Dhaka')::date, f.location_id, 'Supplier refund'::text, null::text, not f.voided, public._acct_today(), null::text, null::text,
    case when not f.voided then jsonb_build_array(jsonb_build_object('a', public._m_key(f.money_account_id, public._acct_paykey(f.mode, true)), 'd', f.amount) /* bos87 */,
      jsonb_build_object('a', 'payable', 'c', f.amount, 'pt', 'supplier', 'pid', f.supplier_id::text)) end
  from public.supplier_refunds f
  where (f.refunded_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_refund', f.id::text, not f.voided);

  -- 10-2 expense vouchers (approved; a re-opened or re-numbered voucher is reversed, the new revision posted)
  return query
  select 'expense_voucher'::text, e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.entry_date, e.location_id, ('Expense voucher ' || e.serial)::text, null::text, v.total > 0, public._acct_today(),
    case when v.bad > 0 then 'unreadable_lines' end, null::text,
    case when v.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'exp_' || h.head, 'd', h.amt) j from (
          select regexp_replace(lower(coalesce(nullif(btrim(x->>'head'), ''), 'other')), '[^a-z0-9_]', '_', 'g') head, sum(public._acct_num(x->>'amount')) amt
          from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x
          where public._acct_num(x->>'amount') > 0 group by 1) h
        union all select 2, jsonb_build_object('a', public._m_key(public._m_id(e.data ->> 'money_account_id'), public._acct_paykey(v.pm, true) /* bos85 */) /* bos87 */, 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select case when e.data->>'pay_mode' in ('cash', 'bank', 'mobile', 'card') then e.data->>'pay_mode' else 'cash' end pm, /* bos85: how the voucher was paid; none = cash as before */
           coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
           count(*) filter (where coalesce(btrim(x->>'amount'), '') <> '' and public._acct_num(x->>'amount') is null) bad
    from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x) v
  where e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'journal') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date >= p_start and public._acct_need('expense_voucher', e.id::text || ':' || coalesce(e.rev_no, 0)::text, v.total > 0);
  return query
  select 'expense_voucher'::text, je.source_id, je.entry_date, je.location_id, 'Expense voucher no longer approved'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'expense_voucher' and je.reverses_id is null
    and not exists (select 1 from public.entries e where e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'journal') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);

  -- bos50: quick expenses typed in the day-book tab: expense head debit, cash / bank / mobile credit
  return query
  select 'quick_expense'::text, q.id::text, q.exp_date, q.location_id, ('Quick expense: ' || q.head)::text, null::text, q.status = 'done', (q.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when q.status = 'done' then jsonb_build_array(
      jsonb_build_object('a', case when exists (select 1 from public.acct_mappings m where m.key = 'exp_' || q.head) then 'exp_' || q.head else 'exp_other' end, 'd', q.amount),
      jsonb_build_object('a', public._m_key(q.money_account_id, public._acct_paykey(q.mode)), 'c', q.amount) /* bos87 */) end
  from public.quick_expenses q
  where q.exp_date >= p_start and public._acct_need('quick_expense', q.id::text, q.status = 'done');

  -- cash moves (bank deposit / withdraw, owner top-up / draw, customer advances, hub receipt)
  return query
  select 'cash_move'::text, public._acct_sid52('cash_move', m.id::text) /* bos52 */, m.move_date, m.location_id, ('Cash move: ' || m.kind)::text, m.kind, m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */, (m.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */ then case m.kind
      when 'bank_deposit' then jsonb_build_array(jsonb_build_object('a', 'pay_bank', 'd', m.amount), jsonb_build_object('a', 'pay_cash', 'c', m.amount))
      when 'bank_withdraw' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'pay_bank', 'c', m.amount))
      when 'owner_topup' then jsonb_build_array(jsonb_build_object('a', public._m_key(m.money_account_id, public._acct_paykey(m.mode)) /* bos87 */, 'd', m.amount), jsonb_build_object('a', 'owner_capital', 'c', m.amount))
      when 'owner_draw' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', m.amount), jsonb_build_object('a', public._m_key(m.money_account_id, public._acct_paykey(m.mode)) /* bos87 */, 'c', m.amount))
      when 'cust_advance' then jsonb_build_array(jsonb_build_object('a', public._m_key(m.money_account_id, public._acct_paykey(m.mode)) /* bos87 */, 'd', m.amount), jsonb_build_object('a', 'cust_advance', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'cust_advance_refund' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', public._m_key(m.money_account_id, public._acct_paykey(m.mode)) /* bos87 */, 'c', m.amount))
      when 'cust_advance_used' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', 'receivable', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'hub_receipt' then jsonb_build_array(jsonb_build_object('a', public._m_key(m.money_account_id, 'pay_cash'), 'd', m.amount), jsonb_build_object('a', 'hub_clearing', 'c', m.amount))
    end end
  from public.cash_moves m
  where m.move_date >= p_start and public._acct_need('cash_move', public._acct_sid52('cash_move', m.id::text), m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */);

  -- wastage at the real cost in the stock ledger
  return query
  select 'wastage'::text, w.id::text, (w.made_at at time zone 'Asia/Dhaka')::date, w.location_id, 'Wastage written off'::text, null::text, true, null::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when c.amt is null or c.amt <= 0 then 'cost_missing' end,
    case when c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'wastage', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['wastage'], w.id::text, array['wastage'], -1) z where z.amt > 0 /* bos72 */
      ) y) end
  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done' and not c.zero103 /* bos103 */, (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) and not c.known103 /* bos103: every ingredient line is a real cost or a free-cost item */ then 'cost_missing' end,
    case when r.status = 'done' and (c.amt > 0 or (c.known103 and not c.zero103)) /* bos103 */ then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', coalesce(c.amt, 0) + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */ /* bos103 */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['production'], r.id::text, array['issue_out'], -1) z where z.amt > 0 /* bos72 */
        union all select 3, jsonb_build_object('a', 'overhead_absorbed', 'c', round(r.conversion_cost, 2)) where coalesce(r.conversion_cost, 0) >= 0.005 /* bos74: Cr overhead absorbed */
      ) y) end
  from public.production_runs r cross join lateral (
    select q.amt, q.nulls, (q.nulls = 0 and q.n > 0) as known103, (q.nulls = 0 and q.n > 0 and coalesce(q.amt, 0) <= 0 and round(coalesce(r.conversion_cost, 0), 2) < 0.005) as zero103 from (   /* bos103: known103 = no unknown cost; zero103 = known and nothing to book */
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */, count(*) n
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') q) c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done' and not c.zero103 /* bos103 */);

  -- bos52: payroll payments of the app payroll (a run whose sheet is the record, i.e. the run is a locked shadow, is skipped). Dr salary expense, Cr cash / bank / mobile.
  -- The advance recovery on the pay line is split over the payments pro rata and credited to the staff-advance asset (data: payroll_lines.advance_recovery).
  return query
  select 'payroll_payment'::text, public._acct_sid52('payroll_payment', p.id::text), p.pay_date, p.location_id, ('Salary payment PR-' || p.run_id::text)::text, null::text,
    p.status = 'done' and not public._c_run_skip(p.run_id) /* bos85 */, (p.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when p.status = 'done' and not public._c_run_skip(p.run_id) /* bos85 */ then
      jsonb_build_array(jsonb_build_object('a', 'salary_exp', 'd', p.amount + r.rec, 'pt', 'staff', 'pid', p.employee_id::text),
                        jsonb_build_object('a', public._m_key(p.money_account_id, public._c_salary_paykey(p.mode)), 'c', p.amount /* bos85 */))
      || case when r.rec > 0 then jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'c', r.rec, 'pt', 'staff', 'pid', p.employee_id::text)) else '[]'::jsonb end
    end
  from public.payroll_payments p
  cross join lateral (select case when l.advance_recovery > 0 and l.net > 0 then least(round(l.advance_recovery * p.amount / l.net, 2), l.advance_recovery) else 0 end as rec
                        from public.payroll_lines l where l.id = p.line_id) r
  where p.pay_date >= p_start
    and public._acct_need('payroll_payment', public._acct_sid52('payroll_payment', p.id::text), p.status = 'done' and not public._c_run_skip(p.run_id) /* bos85 */);

  -- bos52: staff advances paid out of the business (cash / bank / mobile only; mode none = money not moved here, nothing posted). Dr staff advances, Cr cash / bank / mobile.
  return query
  select 'staff_advance'::text, a.id::text, a.adv_date, a.location_id, ('Staff advance ADV-' || a.id::text)::text, null::text,
    a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'), (a.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when a.status = 'active' and a.mode in ('cash', 'bank', 'mobile') then
      jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'd', a.amount, 'pt', 'staff', 'pid', a.employee_id::text),
                        jsonb_build_object('a', public._m_key(a.money_account_id, public._acct_paykey(a.mode)), 'c', a.amount)) end
  from public.employee_advances a
  where a.adv_date >= p_start and public._acct_need('staff_advance', a.id::text, a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'));

  -- bos52: partner capital (contribution / return of capital / loan in / loan repayment / owner drawing). The partner-capital record that is a locked shadow of a cash move
  -- is not posted (the cash move is the record then). A partner-capital record that is the primary of a cash-move shadow takes the place of the cash move (same place, once).
  -- In-kind contributions move no money: they are reported as waiting (in_kind), nothing is guessed.
  return query
  select 'partner_capital'::text, public._acct_sid52('partner_capital', c.id::text), c.cap_date, nullif(lk.loc, 0), ('Partner capital: ' || c.kind)::text, c.kind,
    c.status = 'posted' and not public._shadowed52('partner_capital', c.id::text), (c.void_at at time zone 'Asia/Dhaka')::date, null::text,
    case when c.mode = 'in_kind' then 'in_kind' end,
    case when c.status = 'posted' and c.mode <> 'in_kind' and not public._shadowed52('partner_capital', c.id::text) then case c.kind
      when 'contribution' then jsonb_build_array(jsonb_build_object('a', public._m_key(c.money_account_id, public._acct_paykey(c.mode)), 'd', c.amount), jsonb_build_object('a', 'owner_capital', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'return_of_capital' then jsonb_build_array(jsonb_build_object('a', 'owner_capital', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._m_key(c.money_account_id, public._acct_paykey(c.mode)), 'c', c.amount))
      when 'loan_in' then jsonb_build_array(jsonb_build_object('a', public._m_key(c.money_account_id, public._acct_paykey(c.mode)), 'd', c.amount), jsonb_build_object('a', 'partner_loan', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'loan_repayment' then jsonb_build_array(jsonb_build_object('a', 'partner_loan', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._m_key(c.money_account_id, public._acct_paykey(c.mode)), 'c', c.amount))
      when 'owner_drawing' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._m_key(c.money_account_id, public._acct_paykey(c.mode)), 'c', c.amount))
    end end
  from public.partner_capital c
  left join lateral (select x.location_id as loc from public.shadow_links x where x.primary_type = 'partner_capital' and x.primary_id = c.id::text and x.shadow_type = 'cash_moves'
                      and x.shadow_id is not null and x.state <> 'void' order by x.id limit 1) lk on true
  where c.cap_date >= p_start and public._acct_need('partner_capital', public._acct_sid52('partner_capital', c.id::text), c.status = 'posted' and not public._shadowed52('partner_capital', c.id::text));
  -- bos85: sources of phases 81, 82, 83 (cash short / transit short, salary accrual + partner settlement, mobile wallets)
  return query select * from public._b_docs(p_start); /* bos85 */
  return query select * from public._c_docs(p_start); /* bos85 */
  return query select * from public._d_acct_docs(p_start); /* bos85 */
  return query select * from public._m_docs(p_start); /* bos87: transfers and charges between money accounts */
  return query select * from public._w1f_docs(p_start); /* bos96: other income */

  -- bos85: stock movements that had no document: count adjustment, opening stock, own-use issue, location transfers (one entry per stock-ledger row, source_id = ledger id)
  return query
  select t.st, m.lid::text, m.d, m.loc,
    ((case m.cls when 'adjust' then 'Stock count adjustment' when 'opening' then 'Opening stock' when 'issue' then 'Stock issued for own use' when 'prodin' then 'Production-in without recipe' else 'Stock transfer' end) /* bos103 */ || case when m.rev then ' (reversal)' else '' end)::text,
    null::text, true, null::date, null::text, case when m.nocost then 'cost_missing' end,
    case when not m.nocost then jsonb_build_array(
      jsonb_build_object('a', case when m.qty < 0 then m.xkey else m.ikey end, 'd', m.amt),
      jsonb_build_object('a', case when m.qty < 0 then m.ikey else m.xkey end, 'c', m.amt)) end
  from public._acct_stock_moves85(p_start) m
  cross join lateral (select (case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening' when 'issue' then 'stock_issue' when 'prodin' then 'stock_prodin' else 'stock_transfer' end)::text st /* bos103 */) t
  where public._acct_need(t.st, m.lid::text, true);

  -- bos85: goods short on a received transfer: Dr transit loss / Cr clearing (location-tagged transfers) or inventory
  return query
  select 'transit_loss'::text, t.id::text, (t.received_at at time zone 'Asia/Dhaka')::date, case when public.rule_txt('acct_transit_loss_at') = 'sender' then t.from_location_id else t.to_location_id end,
    'Stock short in transit'::text, null::text, true, null::date, null::text, case when c.nulls > 0 then 'cost_missing' end,
    case when c.nulls = 0 then jsonb_build_array(
      jsonb_build_object('a', 'transit_loss', 'd', c.l),
      jsonb_build_object('a', case when coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' then 'interloc_clearing' else public._acct_inv_key(it.item_type) end, 'c', c.l)) end
  from public.stock_transfers t join public.items it on it.id = t.item_id cross join lateral (
    select coalesce(sum(round(-s.qty_delta * s.unit_cost, 2)) filter (where s.reason = 'transfer_out'), 0) - coalesce(sum(round(s.qty_delta * s.unit_cost, 2)) filter (where s.reason = 'transfer_in'), 0) l,
           count(*) filter (where s.reason in ('transfer_out', 'transfer_in') and coalesce(s.unit_cost, 0) = 0) nulls
    from public.stock_ledger_eff96 s /* bos96 */ where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')
      and (not public.rule_on('transit_loss_gl_fix') or s.client_id is distinct from md5(t.id::text || ':tl_in')::uuid) /* b2s115:docs */) c
  where public.rule_on('acct_transit_loss') and t.status = 'received' and t.received_qty < t.qty
    and (t.received_at at time zone 'Asia/Dhaka')::date >= greatest(p_start, coalesce(public._acct_from85(), p_start)) and (c.nulls > 0 or c.l >= 0.01)
    and public._acct_need('transit_loss', t.id::text, true);

  -- bos85: purchase return price variance (stock left at ledger cost, supplier credit was at bill price)
  return query
  select 'purchase_variance'::text, b.id::text, b.bill_date, b.location_id, ('Purchase return price variance ' || coalesce(b.bill_no, '-'))::text, null::text, b.status = 'posted' and b.total > 0,
    (b.void_at at time zone 'Asia/Dhaka')::date, null::text, case when b.status = 'posted' and b.total > 0 and v.nulls > 0 then 'cost_missing' end,
    case when b.status = 'posted' and b.total > 0 and v.nulls = 0 then v.lines end
  from public.purchase_bills b cross join lateral public._pvar85(b.id) v
  where b.kind = 'return' and b.bill_date >= greatest(p_start, coalesce(public._acct_from85(), p_start)) and public.rule_on('acct_purchase_variance')
    and case when b.status = 'posted' and b.total > 0 then (v.nulls > 0 or v.nonzero) and public._acct_need('purchase_variance', b.id::text, true) else public._acct_need('purchase_variance', b.id::text, false) end;

  -- bos85: card settlement (typed by the person): Dr bank (net), Dr bank charges (fee), Cr card receivable (gross)
  return query
  select 'card_settlement'::text, c.id::text, c.settle_date, c.location_id, 'Card settlement'::text, null::text, c.status = 'done', (c.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when c.status = 'done' then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', public._acct_paykey(c.bank_mode), 'd', c.gross - c.fee) j
        union all select 2, jsonb_build_object('a', 'bank_charges', 'd', c.fee) where c.fee > 0
        union all select 3, jsonb_build_object('a', 'pay_card', 'c', c.gross)) x) end
  from public.card_settlements85 c
  where c.settle_date >= p_start and public._acct_need('card_settlement', c.id::text, c.status = 'done');

  -- bos97: landed cost (freight, duty, insurance ... added to the item cost). One entry once it is posted: Dr inventory raw / pack / finished (the part still on the shelf),
  -- Dr landed_variance (the part already sold), Dr expense / vat_input (charges that are not capitalised); Cr landed_payable / cash / bank / mobile. Lines come from the append-only landed_cost_alloc rows.
  return query
  select 'landed_cost'::text, c.id::text, c.cost_date, c.location_id, ('Landed cost ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'post')
  from public.landed_costs c
  where c.status in ('posted', 'void') and c.posted_at is not null and c.cost_date >= p_start and public._acct_need('landed_cost', c.id::text, true);

  -- bos97: a voided landed cost has its own counter entry (the sold part is released from the variance account, only what is still on the shelf leaves the inventory account)
  return query
  select 'landed_cost_void'::text, c.id::text, (c.void_at at time zone 'Asia/Dhaka')::date, c.location_id, ('Landed cost void ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'void')
  from public.landed_costs c
  where c.status = 'void' and c.posted_at is not null and (c.void_at at time zone 'Asia/Dhaka')::date >= p_start
    and exists (select 1 from public.journal_entries e where e.source_type = 'landed_cost' and e.source_id = c.id::text and e.reverses_id is null)
    and public._acct_need('landed_cost_void', c.id::text, true);

  -- bos113: a drawer count difference reaches the books (rule drawer_short_post = on; default off = as before, the difference is only the yellow / red exception flag).
  --   Short (count < expected): Dr cash short / over (5800), Cr cash. Over: Dr cash, Cr 5800. One entry per final (submitted / approved) form 14-1 revision; a form that is no longer final is reversed by the second query.
  return query
  select 'cash_variance'::text, e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.entry_date, e.location_id,
    (case when k.diff < 0 then 'Cash short, drawer count ' else 'Cash over, drawer count ' end || e.entry_date::text)::text, null::text, true, null::date, null::text, null::text,
    case when k.diff < 0 then jsonb_build_array(jsonb_build_object('a', 'cash_short', 'd', -k.diff), jsonb_build_object('a', 'pay_cash', 'c', -k.diff))
         else jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', k.diff), jsonb_build_object('a', 'cash_short', 'c', k.diff)) end
  from public.entry_counts k join public.entries e on e.id = k.entry_id
  where k.section = 'drawer' and k.diff <> 0 and e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date >= p_start
    and coalesce(public.rule_txt('drawer_short_post'), 'off') = 'on'
    and public._acct_need('cash_variance', e.id::text || ':' || coalesce(e.rev_no, 0)::text, true);
  return query
  select 'cash_variance'::text, je.source_id, je.entry_date, je.location_id, 'Drawer count no longer final'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'cash_variance' and je.reverses_id is null
    and not exists (select 1 from public.entry_counts k join public.entries e on e.id = k.entry_id
                     where k.section = 'drawer' and k.diff <> 0 and e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);
end $function$$r0_0$, null),
  ('public._acct_docs(date)', 'known', '5a0a9057b8c83c3ac7ae5b3b0d7efc09', null),
  ('public._acct_docs(date)', 'known', '92853940c471e24bd48b9b4f1b2ba32c', null),
  ('public._acct_docs(date)', 'known', '9b3e7e1c565114553cca06f6fe513eff', null),
  ('public._acct_docs(date)', 'old', $o0_0$AS $function$
begin$o0_0$, $n0_0$AS $function$
-- bos97: phase515 body + two landed-cost blocks at the end (landed_cost, landed_cost_void)
-- bos103: production run whose ingredients are all free-cost = known cost 0 (posts conversion only, or nothing when there is none); production-in without recipe via _acct_stock_moves85
-- bos98: merged by phase524 = phase515 body + every bos96 line (stock_ledger_eff96 reads) + both bos97 blocks, so neither phase522 nor phase523 can erase the other
-- bos89: merge of phase506 (free-cost) and phase511 (stock moves, card, voucher mode) bodies; every bos50/52/72/74/80/85 line kept
begin$n0_0$),
  ('public._acct_docs(date)', 'old', $o1_0$                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0)) then 'cogs_missing' end, /* bos72: cost 0 = unknown */
    null::text,$o1_0$, $n1_0$                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
    null::text,$n1_0$),
  ('public._acct_docs(date)', 'old', $o2_0$                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0)) then 'cogs_missing' end, /* bos72: cost 0 = unknown */
    null::text,$o2_0$, $n2_0$                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
    null::text,$n2_0$),
  ('public._acct_docs(date)', 'old', $o3_0$          where public._acct_num(x->>'amount') > 0 group by 1) h
        union all select 2, jsonb_build_object('a', public._m_key(public._m_id(e.data ->> 'money_account_id'), 'pay_cash'), 'c', v.total) /* bos87 */
      ) y) end
  from public.entries e cross join lateral (
    select coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
           count(*) filter (where coalesce(btrim(x->>'amount'), '') <> '' and public._acct_num(x->>'amount') is null) bad$o3_0$, $n3_0$          where public._acct_num(x->>'amount') > 0 group by 1) h
        union all select 2, jsonb_build_object('a', public._m_key(public._m_id(e.data ->> 'money_account_id'), public._acct_paykey(v.pm, true) /* bos85 */) /* bos87 */, 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select case when e.data->>'pay_mode' in ('cash', 'bank', 'mobile', 'card') then e.data->>'pay_mode' else 'cash' end pm, /* bos85: how the voucher was paid; none = cash as before */
           coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
           count(*) filter (where coalesce(btrim(x->>'amount'), '') <> '' and public._acct_num(x->>'amount') is null) bad$n3_0$),
  ('public._acct_docs(date)', 'old', $o4_0$  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0) nulls /* bos72 */
    from public.stock_ledger l where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);$o4_0$, $n4_0$  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);$n4_0$),
  ('public._acct_docs(date)', 'old', $o5_0$  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) then 'cost_missing' end,
    case when r.status = 'done' and c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)$o5_0$, $n5_0$  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done' and not c.zero103 /* bos103 */, (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) and not c.known103 /* bos103: every ingredient line is a real cost or a free-cost item */ then 'cost_missing' end,
    case when r.status = 'done' and (c.amt > 0 or (c.known103 and not c.zero103)) /* bos103 */ then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', coalesce(c.amt, 0) + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */ /* bos103 */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)$n5_0$),
  ('public._acct_docs(date)', 'old', $o6_0$  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0) nulls /* bos72 */
    from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done');
$o6_0$, $n6_0$  from public.production_runs r cross join lateral (
    select q.amt, q.nulls, (q.nulls = 0 and q.n > 0) as known103, (q.nulls = 0 and q.n > 0 and coalesce(q.amt, 0) <= 0 and round(coalesce(r.conversion_cost, 0), 2) < 0.005) as zero103 from (   /* bos103: known103 = no unknown cost; zero103 = known and nothing to book */
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */, count(*) n
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') q) c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done' and not c.zero103 /* bos103 */);
$n6_0$),
  ('public._acct_docs(date)', 'old', $o7_0$  return query select * from public._w1f_docs(p_start); /* bos96: other income */
end $function$$o7_0$, $n7_0$  return query select * from public._w1f_docs(p_start); /* bos96: other income */

  -- bos85: stock movements that had no document: count adjustment, opening stock, own-use issue, location transfers (one entry per stock-ledger row, source_id = ledger id)
  return query
  select t.st, m.lid::text, m.d, m.loc,
    ((case m.cls when 'adjust' then 'Stock count adjustment' when 'opening' then 'Opening stock' when 'issue' then 'Stock issued for own use' when 'prodin' then 'Production-in without recipe' else 'Stock transfer' end) /* bos103 */ || case when m.rev then ' (reversal)' else '' end)::text,
    null::text, true, null::date, null::text, case when m.nocost then 'cost_missing' end,
    case when not m.nocost then jsonb_build_array(
      jsonb_build_object('a', case when m.qty < 0 then m.xkey else m.ikey end, 'd', m.amt),
      jsonb_build_object('a', case when m.qty < 0 then m.ikey else m.xkey end, 'c', m.amt)) end
  from public._acct_stock_moves85(p_start) m
  cross join lateral (select (case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening' when 'issue' then 'stock_issue' when 'prodin' then 'stock_prodin' else 'stock_transfer' end)::text st /* bos103 */) t
  where public._acct_need(t.st, m.lid::text, true);

  -- bos85: goods short on a received transfer: Dr transit loss / Cr clearing (location-tagged transfers) or inventory
  return query
  select 'transit_loss'::text, t.id::text, (t.received_at at time zone 'Asia/Dhaka')::date, case when public.rule_txt('acct_transit_loss_at') = 'sender' then t.from_location_id else t.to_location_id end,
    'Stock short in transit'::text, null::text, true, null::date, null::text, case when c.nulls > 0 then 'cost_missing' end,
    case when c.nulls = 0 then jsonb_build_array(
      jsonb_build_object('a', 'transit_loss', 'd', c.l),
      jsonb_build_object('a', case when coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' then 'interloc_clearing' else public._acct_inv_key(it.item_type) end, 'c', c.l)) end
  from public.stock_transfers t join public.items it on it.id = t.item_id cross join lateral (
    select coalesce(sum(round(-s.qty_delta * s.unit_cost, 2)) filter (where s.reason = 'transfer_out'), 0) - coalesce(sum(round(s.qty_delta * s.unit_cost, 2)) filter (where s.reason = 'transfer_in'), 0) l,
           count(*) filter (where s.reason in ('transfer_out', 'transfer_in') and coalesce(s.unit_cost, 0) = 0) nulls
    from public.stock_ledger_eff96 s /* bos96 */ where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')
      and (not public.rule_on('transit_loss_gl_fix') or s.client_id is distinct from md5(t.id::text || ':tl_in')::uuid) /* b2s115:docs */) c
  where public.rule_on('acct_transit_loss') and t.status = 'received' and t.received_qty < t.qty
    and (t.received_at at time zone 'Asia/Dhaka')::date >= greatest(p_start, coalesce(public._acct_from85(), p_start)) and (c.nulls > 0 or c.l >= 0.01)
    and public._acct_need('transit_loss', t.id::text, true);

  -- bos85: purchase return price variance (stock left at ledger cost, supplier credit was at bill price)
  return query
  select 'purchase_variance'::text, b.id::text, b.bill_date, b.location_id, ('Purchase return price variance ' || coalesce(b.bill_no, '-'))::text, null::text, b.status = 'posted' and b.total > 0,
    (b.void_at at time zone 'Asia/Dhaka')::date, null::text, case when b.status = 'posted' and b.total > 0 and v.nulls > 0 then 'cost_missing' end,
    case when b.status = 'posted' and b.total > 0 and v.nulls = 0 then v.lines end
  from public.purchase_bills b cross join lateral public._pvar85(b.id) v
  where b.kind = 'return' and b.bill_date >= greatest(p_start, coalesce(public._acct_from85(), p_start)) and public.rule_on('acct_purchase_variance')
    and case when b.status = 'posted' and b.total > 0 then (v.nulls > 0 or v.nonzero) and public._acct_need('purchase_variance', b.id::text, true) else public._acct_need('purchase_variance', b.id::text, false) end;

  -- bos85: card settlement (typed by the person): Dr bank (net), Dr bank charges (fee), Cr card receivable (gross)
  return query
  select 'card_settlement'::text, c.id::text, c.settle_date, c.location_id, 'Card settlement'::text, null::text, c.status = 'done', (c.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when c.status = 'done' then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', public._acct_paykey(c.bank_mode), 'd', c.gross - c.fee) j
        union all select 2, jsonb_build_object('a', 'bank_charges', 'd', c.fee) where c.fee > 0
        union all select 3, jsonb_build_object('a', 'pay_card', 'c', c.gross)) x) end
  from public.card_settlements85 c
  where c.settle_date >= p_start and public._acct_need('card_settlement', c.id::text, c.status = 'done');

  -- bos97: landed cost (freight, duty, insurance ... added to the item cost). One entry once it is posted: Dr inventory raw / pack / finished (the part still on the shelf),
  -- Dr landed_variance (the part already sold), Dr expense / vat_input (charges that are not capitalised); Cr landed_payable / cash / bank / mobile. Lines come from the append-only landed_cost_alloc rows.
  return query
  select 'landed_cost'::text, c.id::text, c.cost_date, c.location_id, ('Landed cost ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'post')
  from public.landed_costs c
  where c.status in ('posted', 'void') and c.posted_at is not null and c.cost_date >= p_start and public._acct_need('landed_cost', c.id::text, true);

  -- bos97: a voided landed cost has its own counter entry (the sold part is released from the variance account, only what is still on the shelf leaves the inventory account)
  return query
  select 'landed_cost_void'::text, c.id::text, (c.void_at at time zone 'Asia/Dhaka')::date, c.location_id, ('Landed cost void ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'void')
  from public.landed_costs c
  where c.status = 'void' and c.posted_at is not null and (c.void_at at time zone 'Asia/Dhaka')::date >= p_start
    and exists (select 1 from public.journal_entries e where e.source_type = 'landed_cost' and e.source_id = c.id::text and e.reverses_id is null)
    and public._acct_need('landed_cost_void', c.id::text, true);

  -- bos113: a drawer count difference reaches the books (rule drawer_short_post = on; default off = as before, the difference is only the yellow / red exception flag).
  --   Short (count < expected): Dr cash short / over (5800), Cr cash. Over: Dr cash, Cr 5800. One entry per final (submitted / approved) form 14-1 revision; a form that is no longer final is reversed by the second query.
  return query
  select 'cash_variance'::text, e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.entry_date, e.location_id,
    (case when k.diff < 0 then 'Cash short, drawer count ' else 'Cash over, drawer count ' end || e.entry_date::text)::text, null::text, true, null::date, null::text, null::text,
    case when k.diff < 0 then jsonb_build_array(jsonb_build_object('a', 'cash_short', 'd', -k.diff), jsonb_build_object('a', 'pay_cash', 'c', -k.diff))
         else jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', k.diff), jsonb_build_object('a', 'cash_short', 'c', k.diff)) end
  from public.entry_counts k join public.entries e on e.id = k.entry_id
  where k.section = 'drawer' and k.diff <> 0 and e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date >= p_start
    and coalesce(public.rule_txt('drawer_short_post'), 'off') = 'on'
    and public._acct_need('cash_variance', e.id::text || ':' || coalesce(e.rev_no, 0)::text, true);
  return query
  select 'cash_variance'::text, je.source_id, je.entry_date, je.location_id, 'Drawer count no longer final'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'cash_variance' and je.reverses_id is null
    and not exists (select 1 from public.entry_counts k join public.entries e on e.id = k.entry_id
                     where k.section = 'drawer' and k.diff <> 0 and e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);
end $function$$n7_0$);
-- _daybook_lines(integer[],integer[],date,date)
insert into _u_plan (fn, kind, a, b) values
  ('public._daybook_lines(integer[],integer[],date,date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._daybook_lines(p_locs integer[], p_sal integer[], p_from date, p_to date)
 RETURNS TABLE(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
 LANGUAGE sql
 STABLE
AS $function$
  -- POS: money taken with a sale (kind sale) and due collections (kind collection); card settles to the bank
  select p.location_id, (p.paid_at at time zone 'Asia/Dhaka')::date, 'in'::text,
         case p.mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end,
         case p.kind when 'collection' then 'collection' else 'sale' end,
         p.amount,
         case when s.receipt is not null then '#' || s.receipt::text end,
         nullif(btrim(concat_ws(' · ', c.name, coalesce(public._m_name(p.money_account_id), p.wallet), p.ref, case when p.cheque_no is not null then 'cheque ' || p.cheque_no end) /* bos97 */), ''), p.created_staff, p.paid_at,
         case when p.sale_id is not null then 'sale' else 'customer' end, coalesce(p.sale_id::text, p.customer_id::text), false, false
    from public.sale_payments p
    left join public.sales s on s.id = p.sale_id
    left join public.customers c on c.id = p.customer_id
   where not p.voided and p.location_id = any (p_locs) and p.amount between 0.01 and 1000000000000
     and p.paid_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and p.paid_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
  union all
  -- supplier payments (with or without a bill)
  select sp.location_id, (sp.paid_at at time zone 'Asia/Dhaka')::date, 'out',
         case sp.mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end,
         case when sp.bill_id is not null then 'bill' else 'supplier' end,
         sp.amount, pb.bill_no, nullif(btrim(concat_ws(' · ', su.name, coalesce(public._m_name(sp.money_account_id), sp.wallet), sp.ref)), ''), sp.created_staff, sp.paid_at,
         case when sp.bill_id is not null then 'bill' else 'supplier' end, coalesce(sp.bill_id::text, sp.supplier_id::text), false, false
    from public.supplier_payments sp
    left join public.suppliers su on su.id = sp.supplier_id
    left join public.purchase_bills pb on pb.id = sp.bill_id
   where not sp.voided and sp.location_id = any (p_locs) and sp.amount between 0.01 and 1000000000000
     and sp.paid_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and sp.paid_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
  union all
  -- 10-2 expense vouchers (submitted or approved): one line per voucher = the sum of its lines
  select e.location_id, e.entry_date, 'out', coalesce(public._m_mode(e.data ->> 'money_account_id'), case when coalesce(public.rule_txt('daybook_align_mode'), 'off') = 'on' then (case e.data ->> 'pay_mode' when 'mobile' then 'mobile' when 'bank' then 'bank' when 'card' then 'bank' else 'cash' end) else 'cash' end) /* bos87 bos113: the money account when one is chosen, else how the voucher was paid as the journal reads it (rule daybook_align_mode) */, 'expense', x.tot, '#' || e.serial::text,
         x.n::text || ' line(s)' || coalesce(' · ' || public._m_name(public._m_id(e.data ->> 'money_account_id')), ''), e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, false
    from public.entries e
    cross join lateral (select coalesce(sum(public._db_num(l -> 'amount')) filter (where public._db_num(l -> 'amount') > 0), 0) as tot,
                               count(*) filter (where public._db_num(l -> 'amount') > 0) as n
                          from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l) x
   where e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'daybook') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_locs)
     and e.entry_date between p_from and p_to and x.tot between 0.01 and 1000000000000
  union all
  -- 10-1 cash handover slips: counted notes - float left behind. Cash leaves the showroom for the hub (hub side is not recorded -> internal).
  select e.location_id, e.entry_date, 'out', 'cash', 'handover', h.amt, '#' || e.serial::text, nullif(btrim(e.data ->> 'carrier'), ''), e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, true, false
    from public.entries e
    cross join lateral (select coalesce(public._db_num(e.data #> '{count,n1000}'), 0) * 1000 + coalesce(public._db_num(e.data #> '{count,n500}'), 0) * 500
        + coalesce(public._db_num(e.data #> '{count,n200}'), 0) * 200 + coalesce(public._db_num(e.data #> '{count,n100}'), 0) * 100
        + coalesce(public._db_num(e.data #> '{count,n50}'), 0) * 50 + coalesce(public._db_num(e.data #> '{count,n20}'), 0) * 20
        + coalesce(public._db_num(e.data #> '{count,n10}'), 0) * 10 + coalesce(public._db_num(e.data #> '{count,n5}'), 0) * 5
        + coalesce(public._db_num(e.data #> '{count,n2}'), 0) * 2 + coalesce(public._db_num(e.data #> '{count,n1}'), 0)
        + coalesce(public._db_num(e.data #> '{count,coin}'), 0) - coalesce(public._db_num(e.data -> 'leave_float'), 0) as amt) h
   where e.form_code = '10-1' and e.status in ('submitted', 'approved') and e.location_id = any (p_locs)
     and e.entry_date between p_from and p_to and h.amt between 0.01 and 1000000000000
  union all
  -- 02-3 staff advances given in cash / bank / mobile (goods and owner's personal money are not business cash). Salary-sensitive.
  select e.location_id, coalesce(public._db_date(a ->> 'date'), e.entry_date), 'out', a ->> 'method', 'advance', public._db_num(a -> 'amount'),
         '#' || e.serial::text, nullif(btrim(concat_ws(' · ', coalesce(pr.full_name, e.data ->> 'staff'), a ->> 'reason')), ''), e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, true
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) a
    left join public.profiles pr on pr.staff_id = e.data ->> 'staff'
   where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal)
     and (a ->> 'method') in ('cash', 'bank', 'mobile') and public._db_num(a -> 'amount') between 0.01 and 1000000000000
     and coalesce(public._db_date(a ->> 'date'), e.entry_date) between p_from and p_to
  union all
  -- 02-2 salary actually paid (receipt acknowledgement lines: net, method, date). Salary-sensitive.
  select e.location_id, coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date), 'out',
         coalesce(nullif(r ->> 'method', ''), e.data ->> 'pay_method'), 'salary', public._db_num(r -> 'net'),
         '#' || e.serial::text, nullif(btrim(r ->> 'name'), ''), e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, true
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'receipts') = 'array' then e.data -> 'receipts' else '[]'::jsonb end) r
   where e.form_code = '02-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_sal)
     and coalesce(nullif(r ->> 'method', ''), e.data ->> 'pay_method') in ('cash', 'bank', 'mobile') and public._db_num(r -> 'net') between 0.01 and 1000000000000
     and coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date) between p_from and p_to
  union all  -- bos85: mobile wallet fees (phase83)
  select * from public._d_daybook_rows(p_locs, p_from, p_to) /* bos85 */
  union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */
  union all select * from public._w1f_daybook_rows(p_locs, p_from, p_to) /* bos96 */
  union all
  -- bos113 (rule daybook_align_mode = on): the card fee kept back at the settlement leaves the bank side of the day book on the settlement day, as the journal posts it (5810)
  select c.location_id, c.settle_date, 'out'::text, 'bank'::text, 'card_settlement'::text, c.fee, null::text, 'card fee'::text, c.created_staff, c.created_at, 'card_settlement'::text, c.id::text, false, false
    from public.card_settlements85 c
   where coalesce(public.rule_txt('daybook_align_mode'), 'off') = 'on' and c.status = 'done' and c.fee between 0.01 and 1000000000000 and c.location_id = any (p_locs) and c.settle_date between p_from and p_to
  union all
  -- bos113 (rule drawer_short_post = on): a final drawer count difference is a cash movement of the day (short = out, over = in)
  select e.location_id, e.entry_date, case when k.diff < 0 then 'out' else 'in' end, 'cash'::text, 'cash_variance'::text, abs(k.diff), '#' || e.serial::text, 'drawer count difference'::text, e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry'::text, e.id::text, false, false
    from public.entry_counts k join public.entries e on e.id = k.entry_id
   where coalesce(public.rule_txt('drawer_short_post'), 'off') = 'on' and k.section = 'drawer' and k.diff <> 0 and e.form_code = '14-1' and e.status in ('submitted', 'approved')
     and e.location_id = any (p_locs) and e.entry_date between p_from and p_to;
$function$$r0_0$, null),
  ('public._daybook_lines(integer[],integer[],date,date)', 'known', '323ad3de5d5a1ac6577bc678a4ec395d', null),
  ('public._daybook_lines(integer[],integer[],date,date)', 'known', '8c430ac963050c2ebd055483dd096355', null),
  ('public._daybook_lines(integer[],integer[],date,date)', 'known', 'a8f59470ceaf856cabd788e834f4a77f', null),
  ('public._daybook_lines(integer[],integer[],date,date)', 'old', $o0_0$  -- 10-2 expense vouchers (submitted or approved): one line per voucher = the sum of its lines
  select e.location_id, e.entry_date, 'out', coalesce(public._m_mode(e.data ->> 'money_account_id'), 'cash') /* bos87 */, 'expense', x.tot, '#' || e.serial::text,
         x.n::text || ' line(s)' || coalesce(' · ' || public._m_name(public._m_id(e.data ->> 'money_account_id')), ''), e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, false$o0_0$, $n0_0$  -- 10-2 expense vouchers (submitted or approved): one line per voucher = the sum of its lines
  select e.location_id, e.entry_date, 'out', coalesce(public._m_mode(e.data ->> 'money_account_id'), case when coalesce(public.rule_txt('daybook_align_mode'), 'off') = 'on' then (case e.data ->> 'pay_mode' when 'mobile' then 'mobile' when 'bank' then 'bank' when 'card' then 'bank' else 'cash' end) else 'cash' end) /* bos87 bos113: the money account when one is chosen, else how the voucher was paid as the journal reads it (rule daybook_align_mode) */, 'expense', x.tot, '#' || e.serial::text,
         x.n::text || ' line(s)' || coalesce(' · ' || public._m_name(public._m_id(e.data ->> 'money_account_id')), ''), e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, false$n0_0$),
  ('public._daybook_lines(integer[],integer[],date,date)', 'old', $o1_0$  union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */
  union all select * from public._w1f_daybook_rows(p_locs, p_from, p_to) /* bos96 */;
$function$$o1_0$, $n1_0$  union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */
  union all select * from public._w1f_daybook_rows(p_locs, p_from, p_to) /* bos96 */
  union all
  -- bos113 (rule daybook_align_mode = on): the card fee kept back at the settlement leaves the bank side of the day book on the settlement day, as the journal posts it (5810)
  select c.location_id, c.settle_date, 'out'::text, 'bank'::text, 'card_settlement'::text, c.fee, null::text, 'card fee'::text, c.created_staff, c.created_at, 'card_settlement'::text, c.id::text, false, false
    from public.card_settlements85 c
   where coalesce(public.rule_txt('daybook_align_mode'), 'off') = 'on' and c.status = 'done' and c.fee between 0.01 and 1000000000000 and c.location_id = any (p_locs) and c.settle_date between p_from and p_to
  union all
  -- bos113 (rule drawer_short_post = on): a final drawer count difference is a cash movement of the day (short = out, over = in)
  select e.location_id, e.entry_date, case when k.diff < 0 then 'out' else 'in' end, 'cash'::text, 'cash_variance'::text, abs(k.diff), '#' || e.serial::text, 'drawer count difference'::text, e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry'::text, e.id::text, false, false
    from public.entry_counts k join public.entries e on e.id = k.entry_id
   where coalesce(public.rule_txt('drawer_short_post'), 'off') = 'on' and k.section = 'drawer' and k.diff <> 0 and e.form_code = '14-1' and e.status in ('submitted', 'approved')
     and e.location_id = any (p_locs) and e.entry_date between p_from and p_to;
$function$$n1_0$);
-- _p27_pl(date,date,integer[])
insert into _u_plan (fn, kind, a, b) values
  ('public._p27_pl(date,date,integer[])', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._p27_pl(d1 date, d2 date, locs integer[])
 RETURNS TABLE(o_m date, o_loc integer, o_gross numeric, o_ret numeric, o_net numeric, o_costed numeric, o_cogs numeric, o_exp numeric, o_sal numeric, o_fixed numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  s as (select x.id, date_trunc('month', x.sale_date)::date as m, x.location_id, x.total, x.subtotal, x.lines from public.sales x
        where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)),
  tot as (select m, location_id, sum(total) as rev from s group by 1, 2),
  ag as (  -- bos72: stock-ledger cost of what was sold (item_costs only as fallback), returns subtracted with their discount share
    select date_trunc('month', h.d)::date as m, h.loc as location_id,
           sum((case h.src when 'sale' then 1 else -1 end) * (h.led_rev + h.fb_rev)) as cr,
           sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as cg
    from public._cogs_lines72(d1, d2, locs) h group by 1, 2),
  rr as (select r.id, date_trunc('month', (r.created_at at time zone 'Asia/Dhaka')::date)::date as m, r.location_id, r.amount, r.lines
         from public.sale_returns r, net_on
         where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  rt as (select m, location_id, sum(amount) as ra from rr group by 1, 2),
  ex as (
    select u.m, u.location_id, sum(u.amt) as amt from (
      select date_trunc('month', e.entry_date)::date as m, e.location_id, public._r2_num(ln -> 'amount') as amt
      from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln
      where e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date between d1 and d2 and e.location_id = any (locs)
      union all  -- bos50: quick expenses
      select date_trunc('month', q.exp_date)::date, q.location_id, q.amount from public.quick_expenses q
      where q.status = 'done' and q.exp_date between d1 and d2 and q.location_id = any (locs)
      union all  -- bos85: mobile wallet fees (phase83), zero rows while the fee treatment is not_posted
      select w.m, w.loc, w.amount from public._d_wallet_fee_rows(d1, d2, locs) w
      union all  /* bos92: wastage, count shrinkage, transit loss, cash short, bill-paid running cost, minus absorbed overhead (zero rows while profit_one_number_on is off) */
      select x.m, x.loc, x.amt from public._w1d_pl_extra(d1, d2, locs) x) u group by 1, 2),
  sa0 as (  -- bos86 (replaces the bos85 comment here): accrual OFF = all 02-2 forms, exactly as before phase85; accrual ON = the 02-2 forms that are not a shadow of an app payroll run + the approved or paid app runs (each salary once)
    select z.m, z.location_id, sum(z.amt) as amt from (
      select date_trunc('month', e.entry_date)::date as m, e.location_id,
             sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
      from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
      where e.form_code = '02-2' and e.status in ('submitted', 'approved') and (not public.rule_on('payroll_accrual_on') or not public.is_shadow('entries', e.id::text)) /* bos85 bos86 */
        and (not public._w1d_salary_app_first() or not exists (select 1 from public.c_salary_by_month(d1, d2, locs) c2 where c2.m = date_trunc('month', e.entry_date)::date and c2.loc = e.location_id)) /* bos93: the sheet is the fallback only where no counted run exists */
        and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2
      union all
      select c.m, c.loc, c.amt from public.c_salary_by_month(d1, d2, locs) c where (public.rule_on('payroll_accrual_on') or public._w1d_salary_app_first()) /* bos85 bos86 bos93 */) z group by 1, 2),
  sa as (  -- bos117: labour already absorbed into product cost (conversion detail 'labour' of the runs) is not charged a second time to the factory branch (switch factory_labour_absorbed117)
    select s0.m, s0.location_id, case when public.rule_on('factory_labour_absorbed117') then greatest(s0.amt - coalesce((select sum((dd ->> 'amount')::numeric) from public.production_runs pr, jsonb_array_elements(coalesce(pr.conversion_detail, '[]'::jsonb)) dd
        where pr.status = 'done' and pr.location_id = s0.location_id and date_trunc('month', (pr.made_at at time zone 'Asia/Dhaka')::date)::date = s0.m and (pr.made_at at time zone 'Asia/Dhaka')::date between d1 and d2
          and dd ->> 'type' = 'labour' and (dd ->> 'amount') is not null), 0), 0) else s0.amt end as amt
    from sa0 s0),
  k as (select m, location_id from tot union select m, location_id from rt union select m, location_id from ex union select m, location_id from sa)
  select k.m, k.location_id,
         coalesce(t.rev, 0), coalesce(x.ra, 0), coalesce(t.rev, 0) - coalesce(x.ra, 0),
         round(coalesce(a.cr, 0), 2), round(coalesce(a.cg, 0), 2),
         e.amt, s2.amt,
         case when fm.v is not null then round(fm.v * (least(d2, (k.m + interval '1 month')::date - 1) - greatest(d1, k.m) + 1)
                / extract(day from (k.m + interval '1 month' - interval '1 day')), 2) end
  from k
  left join tot t on t.m = k.m and t.location_id = k.location_id
  left join rt x on x.m = k.m and x.location_id = k.location_id
  left join ag a on a.m = k.m and a.location_id = k.location_id
  left join ex e on e.m = k.m and e.location_id = k.location_id
  left join sa s2 on s2.m = k.m and s2.location_id = k.location_id
  left join lateral (select public._r2_num(ls.value) as v from public.location_settings ls where ls.location_id = k.location_id and ls.key = 'fixed_cost_month') fm on true;
$function$$r0_0$, null),
  ('public._p27_pl(date,date,integer[])', 'known', '8b6e3e138ccae1a4e0e78321c3cd9a6a', null),
  ('public._p27_pl(date,date,integer[])', 'known', 'a6c9637a42387221374986fbf931209a', null),
  ('public._p27_pl(date,date,integer[])', 'known', 'e230fe7962af686a514e6205f66a757d', null),
  ('public._p27_pl(date,date,integer[])', 'old', $o0_0$      select x.m, x.loc, x.amt from public._w1d_pl_extra(d1, d2, locs) x) u group by 1, 2),
  sa as (  -- bos86 (replaces the bos85 comment here): accrual OFF = all 02-2 forms, exactly as before phase85; accrual ON = the 02-2 forms that are not a shadow of an app payroll run + the approved or paid app runs (each salary once)
    select z.m, z.location_id, sum(z.amt) as amt from ($o0_0$, $n0_0$      select x.m, x.loc, x.amt from public._w1d_pl_extra(d1, d2, locs) x) u group by 1, 2),
  sa0 as (  -- bos86 (replaces the bos85 comment here): accrual OFF = all 02-2 forms, exactly as before phase85; accrual ON = the 02-2 forms that are not a shadow of an app payroll run + the approved or paid app runs (each salary once)
    select z.m, z.location_id, sum(z.amt) as amt from ($n0_0$),
  ('public._p27_pl(date,date,integer[])', 'old', $o1_0$      select c.m, c.loc, c.amt from public.c_salary_by_month(d1, d2, locs) c where (public.rule_on('payroll_accrual_on') or public._w1d_salary_app_first()) /* bos85 bos86 bos93 */) z group by 1, 2),
  k as (select m, location_id from tot union select m, location_id from rt union select m, location_id from ex union select m, location_id from sa)$o1_0$, $n1_0$      select c.m, c.loc, c.amt from public.c_salary_by_month(d1, d2, locs) c where (public.rule_on('payroll_accrual_on') or public._w1d_salary_app_first()) /* bos85 bos86 bos93 */) z group by 1, 2),
  sa as (  -- bos117: labour already absorbed into product cost (conversion detail 'labour' of the runs) is not charged a second time to the factory branch (switch factory_labour_absorbed117)
    select s0.m, s0.location_id, case when public.rule_on('factory_labour_absorbed117') then greatest(s0.amt - coalesce((select sum((dd ->> 'amount')::numeric) from public.production_runs pr, jsonb_array_elements(coalesce(pr.conversion_detail, '[]'::jsonb)) dd
        where pr.status = 'done' and pr.location_id = s0.location_id and date_trunc('month', (pr.made_at at time zone 'Asia/Dhaka')::date)::date = s0.m and (pr.made_at at time zone 'Asia/Dhaka')::date between d1 and d2
          and dd ->> 'type' = 'labour' and (dd ->> 'amount') is not null), 0), 0) else s0.amt end as amt
    from sa0 s0),
  k as (select m, location_id from tot union select m, location_id from rt union select m, location_id from ex union select m, location_id from sa)$n1_0$);
-- _r3q_l3_shop_pnl(date,date,integer[],jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._r3q_l3_shop_pnl(d1 date, d2 date, locs integer[], flt jsonb)
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
    'profit', case when public.rule_on('report_profit_blank_on') /* bos440 */ and (a.ex is null or a.sal is null or a.fx is null or (a.net > 0 and a.costed < a.net)) then null
                    else round(a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0), 2) end,
    'profit_complete', not (a.ex is null or a.sal is null or a.fx is null or (a.net > 0 and a.costed < a.net)),
    'profit_pct', case when a.net > 0 and not (public.rule_on('report_profit_blank_on') and (a.ex is null or a.sal is null or a.fx is null or a.costed < a.net)) then round(100 * (a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0)) / a.net, 2) end,
    'gaps', nullif(concat_ws(', ', case when a.ex is null then 'expenses' end, case when a.sal is null then 'salary' end, case when a.fx is null then 'fixed' end, case when a.net > 0 and a.costed < a.net then 'cogs(uncosted)' end, public._rptb1_loss_gaps(d1, d2, a.o_loc) /* bos401 */), '')) as x
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
$function$$r0_0$, null),
  ('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)', 'known', '35851d5e0867126927acc20eacdf6cbf', null),
  ('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)', 'known', '6558f0168718af880d0aea46b40208a1', null),
  ('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)', 'known', 'c117f72d482259a0b32156f54489a722', null);
do $u532$
declare f record; r record; cur text; body text; rbody text; miss text := ''; st text; nfix int := 0; ok boolean;
begin
  -- Every function of this file is looked at first. A function is in one of these states: DONE (already the merged text), KNOWN (a known older text of one of the two lines: it is replaced by the
  -- merged text), PATCH (not a known text, but every patch site of the fallback is found), MISSING (nothing fits). ALL missing ones are listed in ONE message and nothing is changed.
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then continue; end if;     -- the function does not exist yet: it is created below
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then continue; end if;
    ok := exists (select 1 from _u_plan where fn = f.fn and kind = 'old');
    body := cur;
    for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
      if position(r.b in body) > 0 then continue; end if;
      if position(r.a in body) = 0 then ok := false; exit; end if;
      body := overlay(body placing r.b from position(r.a in body) for length(r.a));
    end loop;
    if not ok then miss := miss || E'\n  ' || f.fn || ' (the text in this database is not one of the known texts and the patch sites are not all there; md5 ' || md5(cur) || ')'; end if;
  end loop;
  if miss <> '' then raise exception 'phase532: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase532: merged text of the two lines', cur);
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then
      execute rbody;
    else
      body := cur;
      for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
        if position(r.b in body) > 0 then continue; end if;
        body := overlay(body placing r.b from position(r.a in body) for length(r.a));
      end loop;
      execute body;
    end if;
    nfix := nfix + 1;
  end loop;
  raise notice 'phase532: % function(s) changed', nfix;
end $u532$;
drop table if exists _u_plan;
