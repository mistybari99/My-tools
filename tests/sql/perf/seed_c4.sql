-- seed_c4.sql (bos120 perf review): scales the phase110 seed up to the owner's volume and fills the data the phase112..118 reports read.
-- Needs: tests/sql/perf/seed.sql + seed_post.sql already run (seedtmp.* helper tables exist). Test data only. Triggers bypassed (replica role).
--   items 557 -> 1369 (231 categories), +30,000 sales (2 years back, before the accounting start), +6,000 production runs (year 2), 6,000 transfers (incl. returns,
--   cancelled, in transit, short), 2,500 customer give-backs, 15,000 quick expenses, 2,400 card settlements, recipe standards, monthly cost pools.
\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-0000000000a1'
\set s '00000000-0000-0000-0000-0000000000a2'
begin;
set session_replication_role = replica;

-- ---------- items: 501..1312 new (total 1369 with the 57 from the phases), 231 categories
create table seedtmp.it2 as
 select i, md5('item'||i)::uuid id, 'P'||lpad(i::text,4,'0') code,
        case when i%9=0 then 'raw_material' when i%11=0 then 'packaging' when i%3=0 then 'finished_good' else 'resale' end ty,
        (20+(i*11%500))::numeric cost, (20+(i*11%500))*1.4 price
 from generate_series(501,1312) i;
insert into items (id, code, name_bn, name_en, category, unit, base_unit, sell_price, is_active, tracked, item_type, source, sellable, count_in_business)
select id, code, 'Item '||i, 'Item '||i, 'cat0', case when ty='raw_material' then 'kg' else 'pc' end, case when ty='raw_material' then 'kg' else 'pc' end,
       case when ty in ('raw_material','packaging') then 0 else price::int end, true, true, ty, case when ty='finished_good' then 'made' else 'bought' end,
       ty in ('resale','finished_good'), true from seedtmp.it2;
update items set category = 'cat'||(abs(hashtext(code)) % 231), category_bn = 'cat'||(abs(hashtext(code)) % 231);
create table seedtmp.itall as
 select i, id, code, ty, cost, price from seedtmp.it where i>=151 union all select i, id, code, ty, cost, price from seedtmp.it2 where ty in ('resale','finished_good');
create index on seedtmp.itall(i);
create table seedtmp.itn as select row_number() over (order by i) n, * from seedtmp.itall;
create unique index on seedtmp.itn(n);
-- opening for the new items (3 places) + purchases without bills (ledger only)
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, made_at, created_by)
select id, loc, 100000, cost, 'opening', 'opening', now()-interval '800 days', :'o' from seedtmp.it2, generate_series(1,3) loc;
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, created_by)
select t.id, 1+(g%3), 20+(g%50), t.cost*(0.95+(g%11)*0.01), 'purchase_in', 'purchase', 'x'||g, now() - ((g*13 % 700) || ' days')::interval - ((g*911 % 80000) || ' seconds')::interval, :'o'
from generate_series(1,12000) g join seedtmp.itn t on t.n = 1 + (g*7 % (select count(*) from seedtmp.itn));

-- ---------- 30,000 more sales (ids 200001..230000), 141..730 days back (before the accounting start = not pending)
create table seedtmp.nl as
select s, k, (select i from seedtmp.itn where n = 1 + least((select count(*) from seedtmp.itn)-1, floor((select count(*) from seedtmp.itn) * power(((hashtext(s::text||':'||k)&2147483647)::numeric/2147483647), 2.2)))::int) item_i,
       1 + (hashtext(s::text||'q'||k)&3) qty
from generate_series(200001,230000) s, generate_series(1,3) k;
create table seedtmp.nsl as
select s, 1+(s%3) loc, 200000 + s receipt,
       (date_trunc('day', now()) - ((141 + (s%590)) || ' days')::interval + (((s::bigint*7919)%80000) || ' seconds')::interval) at_raw
from generate_series(200001,230000) s;
create index on seedtmp.nl(s); create index on seedtmp.nsl(s);
insert into sales (id, client_id, location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, tendered, customer, quick, status, created_by, created_staff,
                   customer_id, sale_type, paid, due_amount)
select md5('sale'||x.s)::uuid, md5('sclient'||x.s)::uuid, x.loc, x.receipt, (x.at_raw at time zone 'Asia/Dhaka')::date, x.at_raw, g.lines, g.sub, 0, g.sub,
       case when x.s%20=0 then 'due' when x.s%5=0 then 'mobile' else 'cash' end, null,
       case when x.s%20=0 then 'Customer '||(1+x.s%200) end, false, case when x.s%100=0 then 'void' else 'done' end, :'s', 'SEL1',
       case when x.s%20=0 then md5('cus'||(1+x.s%200))::uuid end, 'retail', case when x.s%20=0 then 0 else g.sub end, case when x.s%20=0 then g.sub else 0 end
from seedtmp.nsl x join lateral (
   select jsonb_agg(jsonb_build_object('item_id', t.id, 'code', t.code, 'name', 'Item '||t.i, 'unit', 'pc', 'qty', l.qty, 'price', t.price, 'amount', l.qty*t.price, 'override', false) order by l.k) lines,
          sum(l.qty*t.price) sub
   from seedtmp.nl l join seedtmp.itall t on t.i=l.item_i where l.s=x.s) g on true;
update sales set void_at = sold_at + interval '1 hour', void_by = :'o', void_staff='OWN1' where status='void' and void_at is null;
insert into sale_payments (sale_id, customer_id, location_id, kind, mode, amount, paid_at, created_by, created_staff)
select id, customer_id, location_id, 'sale', case pay_mode when 'mobile' then 'mobile' else 'cash' end, total, sold_at, :'s', 'SEL1' from sales where receipt>200000 and pay_mode in ('cash','mobile');
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, created_by)
select t.id, x.loc, -l.qty, t.cost, 'sale_out', 'sale', md5('sale'||x.s)::uuid::text, x.at_raw, :'o'
  from seedtmp.nl l join seedtmp.nsl x on x.s=l.s join seedtmp.itall t on t.i=l.item_i where x.s%100<>0;
-- customer give-backs (sale_return) on 2,500 earlier sale lines
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, created_by)
select t.id, x.loc, 1, t.cost, 'sale_return', 'sale', md5('sale'||x.s)::uuid::text, x.at_raw + interval '2 hours', :'o'
  from seedtmp.nl l join seedtmp.nsl x on x.s=l.s join seedtmp.itall t on t.i=l.item_i where l.k=1 and x.s%12=1 and x.s%100<>0 limit 2500;

-- ---------- 3,000 more production runs (year 2)
create table seedtmp.pr2 as
select 3000+k k, 1+(k%3) loc, 1+(k%20) r, 1+(k%4) batches,
       (date_trunc('day', now()) - ((366 + (k*173)%360) || ' days')::interval + (((k::bigint*6007)%70000) || ' seconds')::interval - interval '5 minutes') at_ from generate_series(1,3000) k;
insert into production_runs (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, yield_std, status, created_by, cost_complete, material_cost, conversion_cost, unit_cost)
select md5('pr'||p.k)::uuid, md5('prc'||p.k)::uuid, p.loc, c.id, c.item_id, p.batches, p.at_, 10*p.batches, 10*p.batches, 'done', :'o', true, 100, 0, 10 from seedtmp.pr2 p join seedtmp.rc c on c.r=p.r;
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, created_by)
select t.id, p.loc, -round(rl.qty*p.batches*1.02,4), t.cost, 'issue_out', 'production', md5('pr'||p.k)::uuid::text, p.at_, :'o'
  from seedtmp.pr2 p join seedtmp.rl rl on rl.r=p.r join seedtmp.it t on t.i=rl.item_i;
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, created_by)
select c.item_id, p.loc, 10*p.batches, 12, 'production_in', 'production', md5('pr'||p.k)::uuid::text, p.at_, :'o' from seedtmp.pr2 p join seedtmp.rc c on c.r=p.r;
-- year-1 runs: yield_std too (the seed leaves it null)
update production_runs set yield_std = yield_base where yield_std is null;

-- ---------- 6,000 transfers: factory/main -> branches, returns, cancelled, in transit, short
create table seedtmp.tr as
select k, case when k%4=0 then 1 else 6 end fl, case when k%4=0 then 2 + (k%2) else 1 + (k%3) end tl,
       (select id from seedtmp.itall where i = 151 + (k*7 % 100)) item_id,
       (select cost from seedtmp.itall where i = 151 + (k*7 % 100)) cost,
       5 + (k%40) qty,
       case when k%20=0 then 'sent' when k%25=0 then 'cancelled' else 'received' end st,
       now() - ((k*3 % 400) || ' days')::interval - ((k*911 % 80000) || ' seconds')::interval sent_at
from generate_series(1,5200) k where case when k%4=0 then 1 else 6 end <> case when k%4=0 then 2 + (k%2) else 1 + (k%3) end;
insert into stock_transfers (id, client_id, from_location_id, to_location_id, item_id, qty, status, received_qty, sent_by, sent_staff, sent_at, received_by, received_staff, received_at, cancelled_by, cancelled_at)
select md5('tr'||k)::uuid, md5('trc'||k)::uuid, fl, tl, item_id, qty, st, case when st='received' then case when k%17=0 then qty-1 else qty end end, :'o', 'OWN1', sent_at,
       case when st='received' then :'o'::uuid end, case when st='received' then 'OWN1' end, case when st='received' then sent_at + interval '6 hours' end,
       case when st='cancelled' then :'o'::uuid end, case when st='cancelled' then sent_at + interval '1 hour' end from seedtmp.tr;
-- returns: branch sends part of a received transfer back to the sender, later
insert into stock_transfers (id, client_id, from_location_id, to_location_id, item_id, qty, status, received_qty, sent_by, sent_staff, sent_at, received_by, received_staff, received_at)
select md5('trr'||k)::uuid, md5('trrc'||k)::uuid, tl, fl, item_id, 2, 'received', 2, :'o', 'OWN1', sent_at + interval '2 days', :'o', 'OWN1', sent_at + interval '2 days 5 hours'
from seedtmp.tr where st='received' and k%6=0;
do $d$ begin if exists (select 1 from information_schema.columns where table_name='stock_transfers' and column_name='kind') then
  execute $q$update stock_transfers t set kind='return', ref_transfer_id=md5('tr'||r.k)::uuid from seedtmp.tr r where t.id=md5('trr'||r.k)::uuid$q$; end if; end $d$;
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, created_by)
select t.item_id, t.from_location_id, -t.qty, c.cost, 'transfer_out', 'transfer', t.id::text, t.sent_at, :'o' from stock_transfers t join seedtmp.itall c on c.id=t.item_id where t.client_id is not null and t.status<>'xx';
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, created_by)
select t.item_id, t.to_location_id, t.received_qty, c.cost, 'transfer_in', 'transfer', t.id::text, t.received_at, :'o' from stock_transfers t join seedtmp.itall c on c.id=t.item_id where t.status='received';
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, created_by)
select t.item_id, t.to_location_id, -(t.qty - t.received_qty), c.cost, 'transit_loss', 'transfer', t.id::text, t.received_at, :'o' from stock_transfers t join seedtmp.itall c on c.id=t.item_id where t.status='received' and t.received_qty < t.qty;
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, reverses_id, created_by)
select o.item_id, o.location_id, -o.qty_delta, o.unit_cost, 'reversal', 'transfer', o.ref_id, t.cancelled_at, o.id, :'o'
  from stock_ledger o join stock_transfers t on t.id::text = o.ref_id where o.ref_type='transfer' and o.reason='transfer_out' and t.status='cancelled';

-- ---------- expenses and card settlements (2 years)
insert into quick_expenses (location_id, exp_date, head, amount, mode, status, created_by, created_staff)
select 1+(g%3), current_date - (g % 730), (array['transport','tea','repair','rent','cleaning','misc'])[1+g%6], 100 + (g*37 % 5000), 'cash', 'done', :'o', 'OWN1' from generate_series(1,15000) g;
insert into card_settlements85 (location_id, settle_date, gross, fee, status, created_by, created_staff)
select 1+(g%3), current_date - (g % 700), 5000 + (g*53 % 40000), 80 + (g%300), 'done', :'o', 'OWN1' from generate_series(1,2400) g;

-- ---------- balances = ledger sums
insert into stock_balance (item_id, location_id, qty, avg_cost)
select l.item_id, l.location_id, sum(l.qty_delta), coalesce(max(l.unit_cost) filter (where l.reason in ('opening','purchase_in')), 0) from stock_ledger l group by 1,2
on conflict (item_id, location_id) do update set qty=excluded.qty, avg_cost=excluded.avg_cost;
reset session_replication_role;
commit;

-- ---------- recipe standards + monthly cost pools (normal mode, real functions)
select set_config('request.jwt.claim.sub', :'o', false) is not null as x \gset
do $d$ begin if to_regprocedure('public.recipe_std_set116(uuid,integer,text)') is not null then perform recipe_std_set116(r.id, l) from recipes r cross join generate_series(1,3) l where r.id in (select id from seedtmp.rc); end if; end $d$;
select count(*) from (select pool_set(l, (date_trunc('month', current_date) - (m||' months')::interval)::date, c.code, 20000 + m*100, 'month', false, null, null)
   from generate_series(1,3) l, generate_series(0,23) m, (select code from cost_component_types where active order by code limit 3) c) q;
analyze;
select (select count(*) from items) items, (select count(distinct category) from items) cats, (select count(*) from sales) sales, (select count(*) from stock_ledger) ledger,
       (select count(*) from stock_transfers) transfers, (select count(*) from production_runs) runs, (select count(*) from factory_cost_pools) pools;
