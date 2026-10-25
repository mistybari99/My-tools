\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-0000000000a1'
\set s '00000000-0000-0000-0000-0000000000a2'
set session_replication_role = replica;
create table seedtmp.ln2 as
select s, k, 151 + least(349, floor(350 * power(((hashtext(s::text||':'||k)&2147483647)::numeric/2147483647), 2.2)))::int item_i, 1 + (hashtext(s::text||'q'||k)&3) qty
from generate_series(100001,100500) s, generate_series(1,3) k;
create index on seedtmp.ln2(s);
create table seedtmp.sl2 as select s, 1+(s%3) loc, ((s-1)/3)+1 receipt, now() - (((s-100000)*2) || ' minutes')::interval at_raw from generate_series(100001,100500) s;
insert into sales (id, client_id, location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, quick, status, created_by, created_staff, sale_type, paid, due_amount)
select md5('sale'||x.s)::uuid, md5('sclient'||x.s)::uuid, x.loc, x.receipt, (x.at_raw at time zone 'Asia/Dhaka')::date, x.at_raw, g.lines, g.sub, 0, g.sub, 'cash', false, 'done', :'s', 'SEL1', 'retail', g.sub, 0
from seedtmp.sl2 x join lateral (
   select jsonb_agg(jsonb_build_object('item_id', t.id, 'code', t.code, 'name', 'Item '||t.i, 'unit', 'pc', 'qty', l.qty, 'price', t.price, 'amount', l.qty*t.price, 'override', false) order by l.k) lines, sum(l.qty*t.price) sub
   from seedtmp.ln2 l join seedtmp.it t on t.i=l.item_i where l.s=x.s) g on true;
insert into sale_payments (sale_id, location_id, kind, mode, amount, paid_at, created_by, created_staff) select id, location_id, 'sale', 'cash', total, sold_at, :'s', 'SEL1' from sales where md5('x') is not null and receipt > 30000;
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, created_by)
select t.id, x.loc, -l.qty, t.cost, 'sale_out', 'sale', md5('sale'||x.s)::uuid::text, x.at_raw, :'o' from seedtmp.ln2 l join seedtmp.sl2 x on x.s=l.s join seedtmp.it t on t.i=l.item_i;
update stock_balance b set qty = b.qty - d.q from (select item_id, location_id, sum(-qty_delta) q from stock_ledger where ref_type='sale' and made_at > now()-interval '2 hours' and created_by=:'o' and ref_id in (select md5('sale'||s)::uuid::text from seedtmp.sl2) group by 1,2) d where d.item_id=b.item_id and d.location_id=b.location_id;
update serials sr set last = greatest(last, (select max(receipt) from sales s where s.location_id=sr.location_id)) where form_code='POS';
reset session_replication_role;
analyze;
select count(*) from sales where receipt>30000;
