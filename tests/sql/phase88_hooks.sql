-- Phase 88 HOOKS (marker bos88) - the exact-text patches of four shared functions that W1-A needs. NOT part of supabase/phase88.sql.
-- Who runs this: the Wave 1 integrator (phase99 re-patch file) after phase88; the W1-A test (supabase/phase88_test.sql) runs it on a scratch database to prove it.
-- Needs phase88 (_w1a_patch and the _w1a_ helpers). Paste-twice safe: a function that already carries the marker bos88 is left alone (prints false).
-- Every patch site is checked: a missing site stops the file with a clear message and changes nothing in that function.
-- With open_parties_link OFF (the default) every patched function returns exactly what it returned before (_w1a_cust_open is 0 and the opening hook does nothing).

-- 1. _cust_bal: the opening due is part of the customer balance. Credit limit check (record_sale2 -> customer_balance), collect_payment ("overpaid") and the sale-return
--    "due first" credit all read this one function.
select public._w1a_patch('public._cust_bal(uuid)'::regprocedure, array[
  $a$select coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)$a$,
  $a$select public._w1a_cust_open(p_customer) /* bos88: opening due */ + coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)$a$]);

-- 2. customer_dues: customers with an opening due (and perhaps no sale) are in the list; the opening is the oldest item, collections clear it first.
select public._w1a_patch('public.customer_dues()'::regprocedure, array[
  $a$select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0),$a$,
  $a$select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) /* bos88 */ - coalesce(c.coll, 0),$a$,
  $a$(select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0))$a$,
  $a$(case when public._w1a_cust_open(cu.id) > coalesce(c.coll, 0) then public._w1a_cust_open_date(cu.id)
              else (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr + public._w1a_cust_open(cu.id) > coalesce(c.coll, 0)) end)$a$,
  $a$from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id$a$,
  $a$from public.customers cu left join t on t.customer_id = cu.id left join c on c.customer_id = cu.id$a$,
  $a$and t.rem - coalesce(c.coll, 0) > 0$a$,
  $a$and coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) - coalesce(c.coll, 0) > 0$a$]);

-- 3. customer_ledger: one first row "opening" (debit = the opening due) so the running balance of the ledger ends at the same figure as the dues list.
select public._w1a_patch('public.customer_ledger(uuid)'::regprocedure, array[
  $a$select s.sold_at at, 'sale'::text kind,$a$,
  $a$select public._w1a_cust_open_at(p_customer) at, 'opening'::text kind, null::text ref, null::int location_id, o.ob debit, 0::numeric credit, 'opening balance'::text note, null::bigint pid /* bos88 */
      from (select public._w1a_cust_open(p_customer) ob) o where o.ob <> 0
    union all
    select s.sold_at at, 'sale'::text kind,$a$]);

-- 4. opening_balance_post: the customer_dues and supplier_dues sections also fill the customer and supplier sub-ledger in the same transaction (only while open_parties_link is ON).
--    !! Do not use phase87 _m_patch here: it stops at once because the function already carries bos87.
select public._w1a_patch('public.opening_balance_post(jsonb,uuid,boolean,boolean)'::regprocedure, array[
  $a$jid := (r->>'id')::bigint; perform public._m_opening_mark(p_json); /* bos87 */$a$,
  $a$jid := (r->>'id')::bigint; perform public._m_opening_mark(p_json); /* bos87 */ perform public._w1a_opening_apply(p_json); /* bos88 */$a$]);
