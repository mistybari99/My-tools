-- Perf seed (test data only, no real names). Same deterministic data for baseline and final DB.
\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-0000000000a1'
\set s '00000000-0000-0000-0000-0000000000a2'
\set m '00000000-0000-0000-0000-0000000000a3'
\timing off

-- ---------- users / rules (normal mode, triggers on)
insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','perf-owner@s.app','{"full_name":"Perf Owner"}'),(:'s','perf-seller@s.app','{"full_name":"Perf Seller"}'),(:'m','perf-mgr@s.app','{"full_name":"Perf Manager"}') on conflict do nothing;
update profiles set status='active';
update profiles set staff_id='OWN1' where id=:'o';
update profiles set staff_id='SEL1' where id=:'s';
update profiles set staff_id='MGR1' where id=:'m';
insert into user_roles values (:'o','owner'),(:'s','salesperson'),(:'m','showroom_manager') on conflict do nothing;
insert into user_locations values (:'s',1),(:'s',2),(:'s',3),(:'m',1),(:'m',2),(:'m',3) on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false) is not null as x \gset
select acct_set_start(current_date - 140) is not null as x2 \gset
select set_rule('accounting_on','true') is null as x3 \gset

-- ---------- seed helper tables
create schema if not exists seedtmp;
drop table if exists seedtmp.it, seedtmp.ln, seedtmp.sl cascade;
create table seedtmp.it as
 select i, md5('item'||i)::uuid id, 'P'||lpad(i::text,4,'0') code,
        case when i<=100 then 'raw_material' when i<=150 then 'packaging' when i<=250 then 'finished_good' else 'resale' end ty,
        case when i<=100 then 10+(i*13%90) when i<=150 then 2+(i%9) when i<=250 then 30+(i*7%300) else 20+(i*11%500) end::numeric cost,
        case when i>=151 then (case when i<=250 then 50+(i*37%800) else (20+(i*11%500))*1.4 end)::int else 0 end::numeric price
 from generate_series(1,500) i;
alter table seedtmp.it add primary key (i);

set session_replication_role = replica;

insert into items (id, code, name_bn, name_en, category, unit, base_unit, sell_price, is_active, tracked, item_type, source, sellable, count_in_business)
select id, code, 'Item '||i, 'Item '||i, 'cat'||(i%12), case when ty='raw_material' then 'kg' else 'pc' end, case when ty='raw_material' then 'kg' else 'pc' end,
       price, true, true, ty, case when ty='finished_good' then 'made' else 'bought' end, i>=151, true
from seedtmp.it;

insert into suppliers (id, name, mobile, credit_days) select md5('sup'||i)::uuid, 'Supplier '||i, '0181'||lpad(i::text,7,'0'), 15 from generate_series(1,200) i;
insert into customers (id, mobile, name, type, credit_limit) select md5('cus'||i)::uuid, '0171'||lpad(i::text,7,'0'), 'Customer '||i, 'retail', 50000 from generate_series(1,200) i;

-- ---------- sales: 20000 sales x 3 lines over 365 days, 3 locations
create table seedtmp.ln as
select s, k, 151 + least(349, floor(350 * power(((hashtext(s::text||':'||k)&2147483647)::numeric/2147483647), 2.2)))::int item_i,
       1 + (hashtext(s::text||'q'||k)&3) qty
from generate_series(1,20000) s, generate_series(1,3) k;
create table seedtmp.sl as
select s, 1+(s%3) loc, ((s-1)/3)+1 receipt,
       (date_trunc('day', now()) - ((s%365) || ' days')::interval + (((s::bigint*7919)%80000) || ' seconds')::interval) at_raw
from generate_series(1,20000) s;
create index on seedtmp.ln(s); create index on seedtmp.sl(s);
update seedtmp.sl set at_raw = least(at_raw, now() - interval '3 minutes');

insert into sales (id, client_id, location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, tendered, customer, quick, status, created_by, created_staff,
                   customer_id, sale_type, paid, due_amount)
select md5('sale'||x.s)::uuid, md5('sclient'||x.s)::uuid, x.loc, x.receipt, (x.at_raw at time zone 'Asia/Dhaka')::date, x.at_raw, g.lines, g.sub, 0, g.sub,
       case when x.s%20=0 then 'due' when x.s%5=0 then 'mobile' else 'cash' end, null,
       case when x.s%20=0 then 'Customer '||(1+x.s%200) end, false, case when x.s%100=0 then 'void' else 'done' end, :'s', 'SEL1',
       case when x.s%20=0 then md5('cus'||(1+x.s%200))::uuid end, 'retail', case when x.s%20=0 then 0 else g.sub end, case when x.s%20=0 then g.sub else 0 end
from seedtmp.sl x join lateral (
   select jsonb_agg(jsonb_build_object('item_id', t.id, 'code', t.code, 'name', 'Item '||t.i, 'unit', 'pc', 'qty', l.qty, 'price', t.price, 'amount', l.qty*t.price, 'override', false) order by l.k) lines,
          sum(l.qty*t.price) sub
   from seedtmp.ln l join seedtmp.it t on t.i=l.item_i where l.s=x.s) g on true;
update sales set void_at = sold_at + interval '1 hour', void_by = :'o', void_staff='OWN1' where status='void';

insert into sale_payments (sale_id, customer_id, location_id, kind, mode, amount, paid_at, created_by, created_staff)
select id, customer_id, location_id, 'sale', case pay_mode when 'mobile' then 'mobile' else 'cash' end, total, sold_at, :'s', 'SEL1' from sales where pay_mode in ('cash','mobile');

insert into serials (form_code, location_id, last) select 'POS', location_id, max(receipt) from sales group by 1,2 on conflict (form_code, location_id) do update set last = excluded.last;

-- ---------- purchases: 5000 bills x 4 lines
create table seedtmp.pb as
select b, 1+(b%3) loc, (current_date - (b%365)) bd, md5('sup'||(1+b%200))::uuid sup from generate_series(1,5000) b;
create table seedtmp.pl as
select b, k,
  case k when 1 then 1+(b%5) when 2 then 1+((b+2)%5) when 3 then 101+(b%50) else 251+(b*13%250) end item_i,
  case k when 4 then 20 else 50 end + (b%7)*10 qty
from generate_series(1,5000) b, generate_series(1,4) k;
create index on seedtmp.pl(b);
insert into purchase_bills (id, client_id, kind, supplier_id, bill_no, bill_date, location_id, status, subtotal, discount, total, paid, created_by, created_staff, posted_by, posted_at)
select md5('pb'||p.b)::uuid, md5('pbc'||p.b)::uuid, 'bill', p.sup, 'B'||p.b, p.bd, p.loc, 'posted', a.tot, 0, a.tot, case when p.b%4=0 then 0 else a.tot end, :'o', 'OWN1', :'o',
       (p.bd::timestamp + interval '12 hours')
from seedtmp.pb p join lateral (select sum(l.qty*t.cost) tot from seedtmp.pl l join seedtmp.it t on t.i=l.item_i where l.b=p.b) a on true;
insert into purchase_lines (bill_id, line_no, item_id, qty, unit, unit_cost, amount, base_qty, unit_cost_base)
select md5('pb'||l.b)::uuid, l.k, t.id, l.qty, case when t.ty='raw_material' then 'kg' else 'pc' end, t.cost, l.qty*t.cost, l.qty, t.cost from seedtmp.pl l join seedtmp.it t on t.i=l.item_i;

-- ---------- recipes (20) and production runs (3000, 8 ingredients each)
create table seedtmp.rc as select r, md5('rcp'||r)::uuid id, (md5('item'||(150+r))::uuid) item_id from generate_series(1,20) r;
create table seedtmp.rl as
select r, k, case when k<=5 then k else 5 + 1 + ((r*3 + k*7) % 94) end item_i, (0.2 + (k%4)*0.1)::numeric qty from generate_series(1,20) r, generate_series(1,8) k;
insert into recipes (id, item_id, version, yield_qty, yield_unit, active, created_by) select id, item_id, 1, 10, 'pc', true, :'o' from seedtmp.rc;
DO $$ begin if exists (select 1 from information_schema.columns where table_name='recipes' and column_name='approved_at') then execute 'update recipes set approved_at = now() - interval ''400 days'', approved_by = created_by'; end if; end $$;
insert into recipe_lines (recipe_id, ingredient_item_id, qty, unit, waste_pct, sort, active)
select c.id, t.id, l.qty, 'kg', 2, l.k, true from seedtmp.rl l join seedtmp.rc c on c.r=l.r join seedtmp.it t on t.i=l.item_i;
create table seedtmp.pr as
select k, 1+(k%3) loc, 1+(k%20) r, 1+(k%4) batches,
       (date_trunc('day', now()) - (((k*173)%360) || ' days')::interval + (((k::bigint*6007)%70000) || ' seconds')::interval - interval '5 minutes') at_ from generate_series(1,3000) k;
create index on seedtmp.rl(r);
insert into production_runs (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, status, created_by)
select md5('pr'||p.k)::uuid, md5('prc'||p.k)::uuid, p.loc, c.id, c.item_id, p.batches, p.at_, 10*p.batches, 'done', :'o' from seedtmp.pr p join seedtmp.rc c on c.r=p.r;

DO $$ begin if exists (select 1 from information_schema.columns where table_name='production_runs' and column_name='material_cost') then execute 'update production_runs set cost_complete=true, material_cost=100, conversion_cost=0, unit_cost=10'; end if; end $$;
-- ---------- stock ledger (one append, ordered by time like the real thing)
create table seedtmp.led as
 -- opening
 select t.id item_id, loc, 100000::numeric qty_delta, t.cost unit_cost, 'opening'::text reason, 'opening'::text ref_type, null::text ref_id, now()-interval '400 days' made_at
   from seedtmp.it t, generate_series(1,3) loc
 union all -- purchases
 select t.id, p.loc, l.qty, t.cost*(0.95+(l.b%11)*0.01), 'purchase_in', 'purchase', md5('pb'||l.b)::uuid::text, p.bd::timestamp+interval '12 hours'
   from seedtmp.pl l join seedtmp.pb p on p.b=l.b join seedtmp.it t on t.i=l.item_i
 union all -- sales
 select t.id, x.loc, -l.qty, t.cost, 'sale_out', 'sale', md5('sale'||x.s)::uuid::text, x.at_raw
   from seedtmp.ln l join seedtmp.sl x on x.s=l.s join seedtmp.it t on t.i=l.item_i where x.s%100<>0
 union all -- production issue_out
 select t.id, p.loc, -round(rl.qty*p.batches*1.02,4), t.cost, 'issue_out', 'production', md5('pr'||p.k)::uuid::text, p.at_
   from seedtmp.pr p join seedtmp.rl rl on rl.r=p.r join seedtmp.it t on t.i=rl.item_i
 union all -- production_in
 select c.item_id, p.loc, 10*p.batches, 12, 'production_in', 'production', md5('pr'||p.k)::uuid::text, p.at_
   from seedtmp.pr p join seedtmp.rc c on c.r=p.r;
-- pad the 5 big items (raw 1..5) to ~20000 ledger rows each with small receipts / wastage lines (NOT count_adjust: those are scanned by the bos85 stock-move branch)
insert into seedtmp.led
select t.id, 1+(g%3), case when g%2=0 then 1 else -1 end, t.cost, case when g%2=0 then 'purchase_in' else 'wastage' end, 'pad', 'pad', now() - ((g*37 % 360) || ' days')::interval - ((g*911 % 80000) || ' seconds')::interval
from seedtmp.it t cross join lateral generate_series(1, 20000 - (select count(*) from seedtmp.led z where z.item_id=t.id and z.reason<>'opening')::int) g where t.i<=5;

insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, created_by)
select item_id, loc, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, :'o' from seedtmp.led order by made_at, item_id;

insert into stock_balance (item_id, location_id, qty, avg_cost)
select l.item_id, l.location_id, sum(l.qty_delta), max(t.cost) from stock_ledger l join seedtmp.it t on t.id=l.item_id group by 1,2 on conflict (item_id, location_id) do update set qty=excluded.qty, avg_cost=excluded.avg_cost;

-- production batches (open batch only for the last 3 runs of each finished item/place)
insert into stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, created_by)
select c.item_id, p.loc, p.at_, 10*p.batches, case when row_number() over (partition by c.item_id, p.loc order by p.at_ desc) <= 3 then 10*p.batches else 0 end, :'o'
from seedtmp.pr p join seedtmp.rc c on c.r=p.r;
update production_runs r set ledger_in_id = (select min(l.id) from stock_ledger l where l.ref_type='production' and l.ref_id=r.id::text and l.reason='production_in');

-- ---------- forms with ledger posts (for unmatched_forms): 3000 issue slips
insert into entries (id, form_code, location_id, serial, entry_date, status, data, created_by, created_staff, source)
select md5('en'||k)::uuid, '04-2', 1+(k%3), k, current_date - ((k*7)%365), 'approved', '{}'::jsonb, :'o', 'OWN1', 'app' from generate_series(1,3000) k;
insert into entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, kind, item_id, item_code, qty_base, sig, status, reason)
select md5('en'||k)::uuid, 1, ln, '04-2', 1+(k%3), 'out', t.id, t.code, 1, 'sig'||k||'-'||ln, 'skipped', 'covered_by_screen'
from generate_series(1,3000) k cross join generate_series(1,2) ln join seedtmp.it t on t.i = case when (k+ln)%3=0 then 1+(k%5) else 6+(k*ln%94) end;

-- ---------- notifications (for urgent_alerts)
insert into notifications (audience, kind, level, title_bn, title_en, key, day, created_at)
select 'owner', 'perf_'||chr(97+k%20), case when k%7=0 then 'bad' else 'info' end, 'x', 'x', 'k'||k, current_date - (k%60), now() - ((k%1440)||' minutes')::interval from generate_series(1,6000) k;

reset session_replication_role;
analyze;
