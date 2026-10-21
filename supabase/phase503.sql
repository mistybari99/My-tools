-- Phase 503 (SW-4) - SWEETS CUSTOMER DUES: an advance that was applied to a sale reduces the customer's due.
-- Paste AFTER phase502. Paste-twice safe (on conflict do nothing, create or replace). Earlier phase files are not edited.
-- Source: the owner's read-only audit of 19 Oct 2026, A4 (cash and accounting) and finding F-17: "customer dues list can fail to net an applied advance:
-- the test showed debt listed after the advance cleared it, and collecting against that visible due could clear the receivable twice".
-- Reproduced on a local throwaway database (before this file): a 500 credit sale, a 300 advance received, the 300 applied (cash move cust_advance_used):
-- customer_dues still shows 500; customer_advances correctly shows 0. The known gap is also written in the header of phase 447.
-- Switch dues_net_advance_on (default OFF). OFF = customer_dues exactly as before. ON = the applied advances of the customer are taken off the due.
-- Not changed here (listed in docs/PLAN_NEXT.md): customer_ledger does not net applied advances either; the card settlement, over-settlement and
-- settled-card void items of the audit are not in this branch (no card settlement code exists here), so they are not touched.

do $g$ begin
  if to_regclass('public.cash_moves') is null or to_regclass('public.sale_payments') is null then raise exception 'phase503 needs the cash moves and sale payments'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort)
select v.key, v.module, 'switch', 'false'::jsonb, null, null, null, null, v.lab_bn, v.lab_mix, v.lab_en, v.hint_bn, v.hint_en, v.srt
  from (values
    ('dues_net_advance_on', 'pos',
     'গ্রাহকের বকেয়া থেকে জমা (advance) বাদ / Customer due takes off applied advances: on', 'গ্রাহকের বকেয়া থেকে জমা (advance) বাদ / Customer due takes off applied advances: on', 'Customer due takes off applied advances: on', 'OFF = the due still shows a sale whose advance was applied (today). ON = the applied advance reduces the due of the customer.', 'OFF = the due still shows a sale whose advance was applied (today). ON = the applied advance reduces the due of the customer.', 5021)
  ) as v(key, module, lab_bn, lab_mix, lab_en, hint_bn, hint_en, srt)
on conflict (key) do nothing;

-- customer_dues: the definition as it stands before this file, plus the applied advances (one union line; nothing when the switch is off)
CREATE OR REPLACE FUNCTION public.customer_dues()
 RETURNS TABLE(id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with s as (
    select x.id, x.customer_id, x.sale_date, x.sold_at,
           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select z.customer_id, sum(z.a) coll from (
          select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0
          union all select customer_id, amount from public.cash_moves where kind = 'cust_advance_used' and status = 'done' and customer_id is not null and public.rule_on('dues_net_advance_on')) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) /* bos88 */ - coalesce(c.coll, 0),
         (case when public._w1a_cust_open(cu.id) > coalesce(c.coll, 0) then public._w1a_cust_open_date(cu.id)
              else (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr + public._w1a_cust_open(cu.id) > coalesce(c.coll, 0)) end)
  from public.customers cu left join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
  where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) and coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) - coalesce(c.coll, 0) > 0
  order by 6 desc;
$function$;
