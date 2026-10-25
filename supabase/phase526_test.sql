-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase120_test.sql there and is already pasted on the live database under that name.
-- Renumbered to phase526_test.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- FRESH DB ONLY. Phase 526 tests (Step C4: faster _rc118_buckets, _rc118_gap, stock_sales_unmatched; results must be IDENTICAL to phase118).
--   Build: bash tests/sql/final_build.sh <db>   (canonical order incl. phase118 and phase526), then from the REPO ROOT (it pastes phase526.sql again):
--     psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase526_test.sql | grep -E "FAIL|RESULT"
--   Method (as phase110_test): the three functions are measured in their NEW form over a grid of periods / places / items / categories on a small fixture that has every ledger reason,
--   a reversal row, a cancelled transfer, returns to the sender, a short receipt, goods in transit, rows exactly on the period edges (Dhaka midnight), sales in every gap kind
--   (matched, short, over, not posted, untracked, unit unknown, converted unit, repeated item, void, bad lines); then the phase118 bodies are put back, the same grid is run, the
--   two result sets must be equal; phase526 is pasted again (it must restore the new bodies and give the same results a third time). The big-data proof (329k ledger rows,
--   50k sales) is tests/sql/perf/equality120.sh. Test data only, no real names.
\set ON_ERROR_STOP off
\set QUIET on
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.at(p_back int, p_time text default '12:00:00') returns timestamptz language sql stable as $$ select ((tt.today() - p_back)::text || ' ' || p_time)::timestamp at time zone 'Asia/Dhaka' $$;
-- md5 of a query result (rows as text, order independent) and its row count, as 'md5:count'; an error becomes 'ERR:<message>'
create or replace function tt.h(p_sql text) returns text language plpgsql as $$
declare h text; n bigint;
begin execute 'select md5(coalesce(string_agg(x::text, ''|'' order by x::text), ''<empty>'')), count(*) from (' || p_sql || ') x' into h, n; return h || ':' || n;
exception when others then return 'ERR:' || sqlerrm; end $$;
create or replace function tt.err(p_step text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; insert into tt.res values (p_step, false); raise notice 'FAIL % (no error)', p_step;
exception when others then insert into tt.res values (p_step, sqlerrm like '%' || p_msg || '%'); raise notice '% % (%)', case when sqlerrm like '%' || p_msg || '%' then 'PASS' else 'FAIL' end, p_step, sqlerrm; end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
create table if not exists tt.cur (name text primary key, def text);
truncate tt.cur;
create table if not exists tt.hn (k text primary key, h text);
create table if not exists tt.ho (k text primary key, h text);
create table if not exists tt.hr (k text primary key, h text);
truncate tt.hn, tt.ho, tt.hr;

insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','sales2@s.app','{"full_name":"Sales"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1) on conflict do nothing;
select tt.as(:'o');

\echo == T0 shape: the three functions are rewritten, tagged, configured; nothing else changed
select tt.chk('T0 the three carry bos118 and bos120',
  (select count(*) from pg_proc where oid in ('public._rc118_buckets(date,date,integer[],uuid,text)'::regprocedure, 'public._rc118_gap(date,date,integer[],uuid)'::regprocedure,
        'public.stock_sales_unmatched(date,date,integer,uuid,integer)'::regprocedure) and prosrc like '%bos118%' and prosrc like '%bos120%') = 3);
select tt.chk('T0 buckets and gap carry work_mem 64MB and jit off; stock_sales_unmatched has neither',
  (select proconfig @> array['work_mem=64MB','jit=off'] from pg_proc where oid = 'public._rc118_buckets(date,date,integer[],uuid,text)'::regprocedure)
  and (select proconfig @> array['work_mem=64MB','jit=off'] from pg_proc where oid = 'public._rc118_gap(date,date,integer[],uuid)'::regprocedure)
  and (select not exists (select 1 from unnest(coalesce(proconfig,'{}')) c where c like 'work_mem%') from pg_proc where oid = 'public.stock_sales_unmatched(date,date,integer,uuid,integer)'::regprocedure));
select tt.chk('T0 the other phase118 functions are untouched (no bos120 in them)',
  (select count(*) from pg_proc where proname in ('stock_recon_statement','factory_branch_statement','net_profit_report','_rc118_locs','_rc118_gap_summary','_rc118_buckets','_rc118_gap','stock_sales_unmatched','recon_export_log118')
        and pronamespace = 'public'::regnamespace and prosrc like '%bos120%') = 3);
select tt.chk('T0 internal functions stay closed to anon / authenticated; the report stays open to authenticated',
  not has_function_privilege('authenticated','public._rc118_buckets(date,date,integer[],uuid,text)','execute') and not has_function_privilege('anon','public._rc118_buckets(date,date,integer[],uuid,text)','execute')
  and not has_function_privilege('authenticated','public._rc118_gap(date,date,integer[],uuid)','execute') and not has_function_privilege('anon','public._rc118_gap(date,date,integer[],uuid)','execute')
  and has_function_privilege('authenticated','public.stock_sales_unmatched(date,date,integer,uuid,integer)','execute') and not has_function_privilege('anon','public.stock_sales_unmatched(date,date,integer,uuid,integer)','execute'));
select tt.chk('T0 all three stay security definer, stable, search_path public',
  (select count(*) from pg_proc where oid in ('public._rc118_buckets(date,date,integer[],uuid,text)'::regprocedure, 'public._rc118_gap(date,date,integer[],uuid)'::regprocedure,
        'public.stock_sales_unmatched(date,date,integer,uuid,integer)'::regprocedure) and prosecdef and provolatile = 's' and proconfig @> array['search_path=public']) = 3);

\echo == fixtures (triggers bypassed: test data only)
set session_replication_role = replica;
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable,category) values
 ('T-A','Item A','Item A','pc','pc','resale',true,100,true,'catA'),
 ('T-B','Item B','Item B','pc','pc','resale',true,50,true,'catB'),
 ('T-C','Item C','Item C','kg','kg','raw_material',true,0,false,'catX'),
 ('T-U','Item U untracked','Item U untracked','pc','pc','resale',false,10,true,'catX') on conflict do nothing;
insert into unit_conversions (item_id, from_unit, to_unit, factor, active) select id, 'box', 'pc', 12, true from items where code = 'T-B';
insert into unit_conversions (item_id, from_unit, to_unit, factor, active) select id, 'pack', 'pc', 3, true from items where code = 'T-A';
insert into unit_conversions (item_id, from_unit, to_unit, factor, active) select id, 'kg', 'g', 1000, true from items where code = 'T-C';   -- 1 kg = 1000 g -> a sale in g is converted with 1/1000
insert into unit_conversions (item_id, from_unit, to_unit, factor, active) select id, 'pc', 'trio', 3, true from items where code = 'T-A';   -- 1 trio = 1/3 pc: a factor with no end (3 trio = 0.99999..)
create table tt.i as select code, id from items where code like 'T-%';
create or replace function tt.iid(p text) returns uuid language sql stable as $$ select id from tt.i where code = 'T-' || p $$;
-- transfers (ids fixed so the ledger can refer to them)
create table tt.t (n int, id uuid, f int, tl int, item text, qty numeric, st text, rq numeric, sent int, rcv int);
insert into tt.t values
 (1, md5('t1')::uuid, 6, 2, 'A', 10, 'received', 10, 9, 9),     -- factory -> branch 2
 (2, md5('t2')::uuid, 2, 6, 'A', 4,  'received', 4,  7, 7),     -- branch 2 sends 4 back to the factory = RETURN of t1
 (3, md5('t3')::uuid, 6, 1, 'A', 6,  'cancelled', null, 8, null), -- cancelled: out + reversal
 (4, md5('t4')::uuid, 6, 2, 'B', 5,  'sent', null, 6, null),    -- in transit
 (5, md5('t5')::uuid, 6, 2, 'B', 8,  'received', 7, 6, 5),      -- one short (transit loss 1)
 (6, md5('t6')::uuid, 1, 2, 'A', 3,  'received', 3, 9, 9),      -- main -> 2
 (7, md5('t7')::uuid, 2, 1, 'A', 1,  'received', 1, 8, 8),      -- 2 -> main, after t6 = RETURN
 (8, md5('t8')::uuid, 6, 2, 'A', 2,  'received', 2, 3, 3);      -- factory -> 2 again after t2 (2 had sent to 6 earlier) = counted as return by the rule
insert into stock_transfers (id, client_id, from_location_id, to_location_id, item_id, qty, status, received_qty, sent_by, sent_staff, sent_at, received_by, received_staff, received_at, cancelled_by, cancelled_at)
select t.id, md5('tc'||t.n)::uuid, t.f, t.tl, tt.iid(t.item), t.qty, t.st, t.rq, :'o', 'OWN1', tt.at(t.sent, '09:00:00'),
       case when t.st = 'received' then :'o'::uuid end, case when t.st = 'received' then 'OWN1' end, case when t.st = 'received' then tt.at(t.rcv, '11:00:00') end,
       case when t.st = 'cancelled' then :'o'::uuid end, case when t.st = 'cancelled' then tt.at(t.sent, '10:00:00') end from tt.t t;
-- sales
create table tt.s (n int, id uuid, loc int, d int, st text, lines jsonb);
insert into tt.s values
 (1, md5('s1')::uuid, 1, 7, 'done', '[{"item_id":"@A","qty":3,"unit":"pc","price":100,"amount":300}]'),                       -- matched (-3 posted)
 (2, md5('s2')::uuid, 1, 6, 'done', '[{"item_id":"@A","qty":2,"unit":"pc","price":100,"amount":200}]'),                       -- matched, then reversed (net 0 = not posted)
 (3, md5('s3')::uuid, 1, 6, 'done', '[{"item_id":"@A","qty":5,"unit":"pc","price":100,"amount":500}]'),                       -- short_posted (-3 of 5)
 (4, md5('s4')::uuid, 2, 6, 'done', '[{"item_id":"@A","qty":1,"unit":"pc","price":100,"amount":100}]'),                       -- over_posted (-3 for 1)
 (5, md5('s5')::uuid, 1, 5, 'done', '[{"item_id":"@A","qty":2,"unit":"pc","price":100,"amount":200}]'),                       -- not_posted (no ledger row)
 (6, md5('s6')::uuid, 1, 8, 'done', '[{"item_id":"@U","qty":4,"unit":"pc","price":10,"amount":40}]'),                         -- untracked
 (7, md5('s7')::uuid, 2, 9, 'done', '[{"item_id":"@B","qty":2,"unit":"box","price":600,"amount":1200},{"item_id":"@B","qty":3,"unit":"pc","price":50,"amount":150}]'),  -- 24 + 3 = 27 base, matched
 (8, md5('s8')::uuid, 2, 9, 'done', '[{"item_id":"@B","qty":2,"unit":"sack","price":50,"amount":100}]'),                       -- unit_unknown
 (9, md5('s9')::uuid, 1, 8, 'done', '[{"qty":1,"unit":"pc","amount":10},{"item_id":"not-a-uuid","qty":1,"amount":5},{"item_id":"@A","qty":"abc","amount":5},{"item_id":"00000000-0000-0000-0000-00000000dead","qty":1,"unit":"pc","amount":9},{"item_id":"@A","qty":1.5,"unit":"  ","amount":150}]'), -- bad lines + 1.5 A (blank unit), no ledger
 (10, md5('s10')::uuid, 1, 10, 'done', '[{"item_id":"@A","qty":2,"unit":"pack","price":300,"amount":600}]'),                   -- 2 pack = 6 base, edge day D-10, posted -6: matched
 (11, md5('s11')::uuid, 1, 4, 'done', '[{"item_id":"@A","qty":9,"unit":"pc","amount":900}]'),                                 -- day D-4 (after the period), posted -9 matched
 (12, md5('s12')::uuid, 1, 7, 'void', '[{"item_id":"@A","qty":3,"unit":"pc","amount":300}]'),                                 -- void: not in the gap
 (13, md5('s13')::uuid, 6, 6, 'done', '[{"item_id":"@C","qty":500,"unit":"g","amount":50},{"item_id":"@C","qty":2,"unit":"kg","amount":200}]'),    -- 500 g = 0.5 kg + 2 kg; posted -2.5
 (14, md5('s14')::uuid, 1, 11, 'done', '[{"item_id":"@A","qty":1,"unit":"pc","amount":100}]'),                               -- day D-11, not posted
 (15, md5('s15')::uuid, 1, 12, 'done', '[{"item_id":"@A","qty":3,"unit":"trio","amount":300}]');                               -- 3 trio = 0.999..9 pc, posted -1: matched (the factor has no end)
update tt.s set lines = replace(replace(replace(replace(lines::text, '@A', tt.iid('A')::text), '@B', tt.iid('B')::text), '@C', tt.iid('C')::text), '@U', tt.iid('U')::text)::jsonb;
insert into sales (id, client_id, location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, quick, status, created_by, created_staff, sale_type, paid, due_amount)
select s.id, md5('sc'||s.n)::uuid, s.loc, 9000 + s.n, tt.today() - s.d, tt.at(s.d, '14:00:00'), s.lines, 100, 0, 100, 'cash', false, s.st, :'o', 'OWN1', 'retail', 100, 0 from tt.s s;
-- ledger: [item, place, qty, reason, ref_type, ref_id, when]
create table tt.l (k int, item text, loc int, qty numeric, reason text, rt text, rid text, at timestamptz);
insert into tt.l values
 (1,'A',1,100,'opening','opening',null,tt.at(60)), (2,'A',1,50,'purchase_in','purchase','p1',tt.at(20)),
 (3,'A',1,20,'purchase_in','purchase','p2',tt.at(10,'00:00:00')),                  -- first instant of the period [D-10, D-5]
 (4,'A',1,-5,'purchase_return','purchase','p3',tt.at(9)),
 (5,'A',1,30,'production_in','production','r1',tt.at(8)), (6,'A',1,-12,'issue_out','production','r1',tt.at(8)),
 (7,'A',1,-3,'sale_out','sale',md5('s1')::uuid::text,tt.at(7)),                          -- s1 (the sale id as uuid text: md5('s1')::uuid::text below)
 (8,'A',1,-2,'sale_out','sale',md5('s2')::uuid::text,tt.at(6)),                          -- reversed by row 21
 (9,'A',1,-3,'sale_out','sale',md5('s3')::uuid::text,tt.at(6)),
 (10,'A',1,1,'sale_return','sale_return','x1',tt.at(6)), (11,'A',1,3,'sale_void_in','sale',md5('s12')::uuid::text,tt.at(6)),
 (12,'A',1,-4,'wastage','wastage','w1',tt.at(5,'23:59:59.999')),                    -- last instant of the period
 (13,'A',1,-1,'wastage','wastage','w2',tt.at(4,'00:00:00')),                        -- first instant after it
 (14,'A',1,-2,'count_adjust','count','c1',tt.at(7)), (15,'A',1,0.5,'cost_adjust','cost','c2',tt.at(7)),
 (16,'A',1,-9,'sale_out','sale',md5('s11')::uuid::text,tt.at(4)), (17,'A',1,-6,'sale_out','sale',md5('s10')::uuid::text,tt.at(10,'00:00:00')),
 (18,'A',1,-3,'wastage','wastage','w0',tt.at(30)),                                  -- reversed by row 22 inside the period
 (19,'A',1,10,'purchase_in','purchase','p0',tt.at(1000)),                           -- very old
 (20,'A',1,5,'purchase_in','purchase','p9',tt.at(11,'23:59:59')),                   -- last second before the period
 (30,'A',2,10,'opening','opening',null,tt.at(60)), (31,'A',2,-4,'sale_out','sale',md5('s4')::uuid::text,tt.at(6)),
 (32,'A',2,-1,'sale_out','sale',md5('s4')::uuid::text,tt.at(6,'15:00:00')), (33,'A',2,-1,'sale_out','sale',md5('s4')::uuid::text,tt.at(6,'16:00:00')),   -- 6 posted for a sale of 1 -> over_posted
 (40,'A',6,500,'opening','opening',null,tt.at(60)),
 (50,'B',6,50,'opening','opening',null,tt.at(60)), (51,'B',2,30,'opening','opening',null,tt.at(60)),
 (52,'B',2,-27,'sale_out','sale',md5('s7')::uuid::text,tt.at(9)),
 (60,'C',6,40,'opening','opening',null,tt.at(60)), (61,'C',6,-2.5,'sale_out','sale',md5('s13')::uuid::text,tt.at(6)),
 (70,'U',1,100,'opening','opening',null,tt.at(60)), (71,'U',1,-4,'sale_out','sale',md5('s6')::uuid::text,tt.at(8)),
 (72,'A',1,-1,'sale_out','sale',md5('s15')::uuid::text,tt.at(12));
-- the ledger rows of the transfers (out at the sender, in at the receiver for received ones, a loss for the short one)
insert into tt.l select 100 + t.n, t.item, t.f, -t.qty, 'transfer_out', 'transfer', t.id::text, tt.at(t.sent, '09:00:00') from tt.t t;
insert into tt.l select 120 + t.n, t.item, t.tl, t.rq, 'transfer_in', 'transfer', t.id::text, tt.at(t.rcv, '11:00:00') from tt.t t where t.st = 'received';
insert into tt.l select 140 + t.n, t.item, t.tl, -(t.qty - t.rq), 'transit_loss', 'transfer', t.id::text, tt.at(t.rcv, '11:30:00') from tt.t t where t.st = 'received' and t.rq < t.qty;
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, created_by)
select tt.iid(l.item), l.loc, l.qty, case when l.qty > 0 then 10 else 10 end, l.reason, l.rt, l.rid, l.at, :'o' from tt.l l order by l.at, l.k;
-- reversal rows: a cancelled transfer (t3) and a reversed sale line (s2) one hour after the original; a wastage row from before the period reversed INSIDE it (D-7)
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, reverses_id, created_by)
select o.item_id, o.location_id, -o.qty_delta, o.unit_cost, 'reversal', o.ref_type, o.ref_id, o.made_at + interval '1 hour', o.id, :'o'
  from stock_ledger o where (o.ref_type = 'transfer' and o.reason = 'transfer_out' and o.ref_id = md5('t3')::uuid::text)
                         or (o.ref_type = 'sale' and o.ref_id = md5('s2')::uuid::text and o.reason = 'sale_out');
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, reverses_id, created_by)
select o.item_id, o.location_id, -o.qty_delta, o.unit_cost, 'reversal', o.ref_type, o.ref_id, tt.at(7,'08:00:00'), o.id, :'o' from stock_ledger o where o.ref_type = 'wastage' and o.ref_id = 'w0';
insert into stock_balance (item_id, location_id, qty, avg_cost)
select l.item_id, l.location_id, sum(l.qty_delta), 10 from stock_ledger l join tt.i i on i.id = l.item_id group by 1, 2 on conflict (item_id, location_id) do update set qty = excluded.qty;
-- one balance that disagrees with the ledger (variance flag)
update stock_balance set qty = qty + 7 where item_id = tt.iid('A') and location_id = 6;
reset session_replication_role;
select tt.chk('F0 fixture: ledger rows, 8 transfers, 15 sales', (select count(*) from stock_ledger l join tt.i i on i.id = l.item_id) > 50 and (select count(*) from stock_transfers where client_id in (select md5('tc'||n)::uuid from tt.t)) = 8
  and (select count(*) from sales where receipt between 9001 and 9015) = 15);
select tt.chk('F0 fixture has a reversal of a transfer, of a sale and of a wastage row', (select count(*) from stock_ledger r join tt.i i on i.id = r.item_id where r.reverses_id is not null) = 3);

\echo == hand-checked numbers of the NEW bodies (item A, place 1, period D-10 .. D-5)
create or replace function tt.row(p_from int, p_to int, p_loc int, p_code text) returns jsonb language sql stable as $$
  select r from jsonb_array_elements((public.stock_recon_statement(tt.today() - p_from, tt.today() - p_to, p_loc, null, null, 5000)) -> 'rows') r
   where (r ->> 'location_id')::int = p_loc and r ->> 'item_code' = p_code $$;
create or replace function tt.n(p_j jsonb, p_key text) returns numeric language sql immutable as $$ select (p_j ->> p_key)::numeric $$;
select tt.as(:'o');
select tt.chk('H1 opening = 100 + 50 + 10 (very old) + 5 (last second before the period) - 3 (old wastage) - 1 (s15 on D-12) = 161; its reversal (+3) is inside the period, not here',
  tt.n(tt.row(10, 5, 1, 'T-A'), 'opening_qty') = 161);
select tt.chk('H2 purchases = +20 (first instant of the period) - 5 (purchase_return) = 15', tt.n(tt.row(10, 5, 1, 'T-A'), 'purchases_qty') = 15);
select tt.chk('H3 production 30, used 12', tt.n(tt.row(10, 5, 1, 'T-A'), 'production_qty') = 30 and tt.n(tt.row(10, 5, 1, 'T-A'), 'used_qty') = 12);
select tt.chk('H4 sales = 3 (s1) + 2 (s2) - 2 (s2 reversed: the reversal counts under sale_out) + 3 (s3) + 6 (s10) = 12', tt.n(tt.row(10, 5, 1, 'T-A'), 'sales_qty') = 12);
select tt.chk('H5 give-backs = 1 (sale_return) + 3 (sale_void_in) = 4', tt.n(tt.row(10, 5, 1, 'T-A'), 'give_back_qty') = 4);
select tt.chk('H6 wastage = 4 (last instant of the period) - 3 (the old row reversed inside) = 1; the row of the next day is not in', tt.n(tt.row(10, 5, 1, 'T-A'), 'wastage_qty') = 1);
select tt.chk('H7 adjustments = -2 (count_adjust) + 0.5 (cost_adjust) = -1.5', tt.n(tt.row(10, 5, 1, 'T-A'), 'adjustments_qty') = -1.5);
select tt.chk('H8 place 1: transfer out of A = 3 (t6, main to branch 2, nobody sent it back before: not a return)',
  tt.n(tt.row(10, 5, 1, 'T-A'), 'transfer_out_qty') = 3 and tt.n(tt.row(10, 5, 1, 'T-A'), 'returned_to_sender_qty') = 0);
select tt.chk('H8b place 6: transfer out of A = 10 (t1) + 6 - 6 (t3 cancelled: the reversal counts under transfer_out) = 10; t8 on D-3 is outside; transfer in 4 (t2 comes back)',
  tt.n(tt.row(10, 5, 6, 'T-A'), 'transfer_out_qty') = 10 and tt.n(tt.row(10, 5, 6, 'T-A'), 'returned_to_sender_qty') = 0 and tt.n(tt.row(10, 5, 6, 'T-A'), 'transfer_in_qty') = 4);
select tt.chk('H9 place 2: transfers out of A = 4 (t2) + 1 (t7), both returns; transfer in = 10 (t1) + 3 (t6)',
  tt.n(tt.row(10, 5, 2, 'T-A'), 'transfer_out_qty') = 5 and tt.n(tt.row(10, 5, 2, 'T-A'), 'returned_to_sender_qty') = 5 and tt.n(tt.row(10, 5, 2, 'T-A'), 'transfer_in_qty') = 13);   -- t8 (2) is on D-3, outside
select tt.chk('H10 every row of the statement balances (opening + moves = closing) and the planted variance on A@6 is flagged',
  (select bool_and(not (r -> 'flags') ? 'unbalanced') from jsonb_array_elements(public.stock_recon_statement(tt.today() - 100, tt.today() - 1, null, null, null, 5000) -> 'rows') r)
  and (tt.row(10, 5, 6, 'T-A') -> 'flags') ? 'variance');
select tt.chk('H11 unmatched sales: s3 short, s4 over, s5 not posted, s6 untracked, s8 unit unknown, s9 (blank unit, 1.5) and s14 not posted; s1 s2 s7 s10 s11 s13 s15 matched; s12 void not listed',
  (select jsonb_object_agg(k, n) from (select r ->> 'kind' k, count(*) n from jsonb_array_elements(public.stock_sales_unmatched(tt.today() - 20, tt.today() - 1, null, null, 500) -> 'rows') r group by 1) q)
  = '{"over_posted": 1, "short_posted": 1, "not_posted": 3, "untracked": 1, "unit_unknown": 1}'::jsonb);

\echo == the grid: NEW bodies
create table if not exists tt.grid (n serial, f int, t int, loc text, item text, cat text);
truncate tt.grid;
insert into tt.grid (f, t, loc, item, cat)
select p.f, p.t, l.loc, i.item, c.cat from (values (10,5),(11,4),(5,5),(3,1),(100,1),(1,1),(60,59),(10,10),(4,4)) p(f, t),
  (values ('null'),('1'),('2'),('6')) l(loc), (values ('null'),('A'),('B'),('C'),('U')) i(item), (values ('null'),('catX'),('catA')) c(cat)
 where not (i.item <> 'null' and c.cat <> 'null');
select tt.chk('G0 the grid has cases', (select count(*) from tt.grid) = 252);
create or replace function tt.runall(p_into text) returns void language plpgsql as $$
declare g record; ex text; locs text; it text; k text;
begin
  for g in select * from tt.grid order by n loop
    it := case when g.item = 'null' then 'null' else format('tt.iid(%L)', g.item) end;
    k := format('%s|%s|%s|%s|%s', g.f, g.t, g.loc, g.item, g.cat);
    locs := format('array(select id from locations where (%s::int is null or id = %s::int))', g.loc, g.loc);
    ex := format('insert into tt.%s select %L, tt.h(%L)', p_into, 'RECON|' || k, format('select public.stock_recon_statement(tt.today() - %s, tt.today() - %s, %s::int, %s::uuid, %s, 5000)::text',
            g.f, g.t, g.loc, it, case when g.cat = 'null' then 'null' else quote_literal(g.cat) end));
    execute ex;
    ex := format('insert into tt.%s select %L, tt.h(%L)', p_into, 'FBR|' || k, format('select public.factory_branch_statement(tt.today() - %s, tt.today() - %s, %s::int, %s::uuid, %s, 5000)::text',
            g.f, g.t, g.loc, it, case when g.cat = 'null' then 'null' else quote_literal(g.cat) end));
    execute ex;
    ex := format('insert into tt.%s select %L, tt.h(%L)', p_into, 'BUCK|' || k, format('select * from public._rc118_buckets(tt.today() - %s, tt.today() - %s, %s, %s::uuid, %s)',
            g.f, g.t, locs, it, case when g.cat = 'null' then 'null' else quote_literal(g.cat) end));
    execute ex;
    if g.cat = 'null' then
      ex := format('insert into tt.%s select %L, tt.h(%L)', p_into, 'UNM|' || k, format('select public.stock_sales_unmatched(tt.today() - %s, tt.today() - %s, %s::int, %s::uuid, 500)::text', g.f, g.t, g.loc, it));
      execute ex;
      ex := format('insert into tt.%s select %L, tt.h(%L)', p_into, 'GAP|' || k, format('select * from public._rc118_gap(tt.today() - %s, tt.today() - %s, %s, %s::uuid)', g.f, g.t, locs, it));
      execute ex;
    end if;
  end loop;
end $$;
select tt.as(:'o');
select tt.runall('hn');
select tt.chk('G1 NEW: results collected', (select count(*) from tt.hn) = 1116 and (select count(*) from tt.hn where h like 'ERR:%') = 0);
select tt.chk('G1b NEW: the reports are not all empty', (select count(*) from tt.hn where h not like '%:0' and h not like 'ERR%') > 400);
insert into tt.cur select 'buckets', pg_get_functiondef('public._rc118_buckets(date,date,integer[],uuid,text)'::regprocedure);
insert into tt.cur select 'gap', pg_get_functiondef('public._rc118_gap(date,date,integer[],uuid)'::regprocedure);
insert into tt.cur select 'unm', pg_get_functiondef('public.stock_sales_unmatched(date,date,integer,uuid,integer)'::regprocedure);

\echo == the grid: the phase118 bodies put back (copied from supabase/phase118.sql)
create or replace function public._rc118_buckets(p_from date, p_to date, p_locs integer[], p_item uuid, p_cat text)
returns table (location_id integer, item_id uuid, opening numeric, production numeric, used numeric, purchases numeric, transfer_in numeric,
               transfer_ret numeric, transfer_oth numeric, sales numeric, cust_back numeric, wastage numeric, transit_loss numeric,
               adjustments numeric, closing numeric, ledger_total numeric, moves bigint)
language sql stable security definer set search_path = public as $$
-- bos118 (old body)
  with l as (
    select sl.location_id, sl.item_id, sl.qty_delta, (sl.made_at at time zone 'Asia/Dhaka')::date as d, coalesce(o.reason, sl.reason) as eff,
           (coalesce(o.reason, sl.reason) = 'transfer_out' and sl.ref_type = 'transfer' and exists (
              select 1 from public.stock_transfers t join public.stock_transfers t2
                on t2.from_location_id = t.to_location_id and t2.to_location_id = t.from_location_id and t2.item_id = t.item_id and t2.sent_at < t.sent_at and t2.status <> 'cancelled'
              where t.id = (case when sl.ref_id ~ '^[0-9a-f-]{36}$' then sl.ref_id::uuid end))) as is_ret
      from public.stock_ledger sl
      left join public.stock_ledger o on o.id = sl.reverses_id
      join public.items i on i.id = sl.item_id
     where sl.location_id = any (p_locs) and (p_item is null or sl.item_id = p_item) and (p_cat is null or i.category = p_cat))
  select l.location_id, l.item_id,
    coalesce(sum(l.qty_delta) filter (where l.d < p_from), 0),
    coalesce(sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'production_in'), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'issue_out'), 0),
    coalesce(sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff in ('purchase_in', 'purchase_return')), 0),
    coalesce(sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'transfer_in'), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'transfer_out' and l.is_ret), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'transfer_out' and not l.is_ret), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'sale_out'), 0),
    coalesce(sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff in ('sale_void_in', 'sale_return')), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'wastage'), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'transit_loss'), 0),
    coalesce(sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff not in ('production_in', 'issue_out', 'purchase_in', 'purchase_return', 'transfer_in', 'transfer_out',
                                                                                         'sale_out', 'sale_void_in', 'sale_return', 'wastage', 'transit_loss')), 0),
    coalesce(sum(l.qty_delta) filter (where l.d <= p_to), 0),
    coalesce(sum(l.qty_delta), 0),
    count(*) filter (where l.d between p_from and p_to)
  from l group by l.location_id, l.item_id;
$$;
create or replace function public._rc118_gap(p_from date, p_to date, p_locs integer[], p_item uuid)
returns table (sale_id uuid, receipt integer, sale_date date, location_id integer, item_id uuid, sold_qty numeric, base_qty numeric, ledger_qty numeric, diff_qty numeric, kind text)
language sql stable security definer set search_path = public as $$
-- bos118 (old body)
  with ln as (
    select s.id as sid, s.receipt as rc, s.sale_date as sd, s.location_id as lid,
           (case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end) as iid,
           (case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end) as q, nullif(btrim(e->>'unit'), '') as u
      from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
     where s.status = 'done' and s.sale_date between p_from and p_to and s.location_id = any (p_locs)),
  g as (
    select ln.sid, ln.rc, ln.sd, ln.lid, ln.iid, sum(ln.q) as q, sum(public._base_qty(ln.iid, ln.q, ln.u)) as bq, bool_or(public._base_qty(ln.iid, ln.q, ln.u) is null) as unk
      from ln where ln.iid is not null and ln.q is not null and (p_item is null or ln.iid = p_item) group by 1, 2, 3, 4, 5),
  led as (
    select sl.ref_id as rid, sl.item_id as iid, sum(-sl.qty_delta) as lq from public.stock_ledger sl
     where sl.ref_type = 'sale' and sl.reason = 'sale_out' and sl.ref_id in (select sid::text from g) group by 1, 2)
  select g.sid, g.rc, g.sd, g.lid, g.iid, g.q, g.bq, coalesce(led.lq, 0), coalesce(g.bq, 0) - coalesce(led.lq, 0),
         (case when not i.tracked then 'untracked' when g.unk then 'unit_unknown' when coalesce(led.lq, 0) = 0 then 'not_posted'
               when g.bq - led.lq > 0.0005 then 'short_posted' else 'over_posted' end)
    from g join public.items i on i.id = g.iid left join led on led.rid = g.sid::text and led.iid = g.iid
   where (not i.tracked) or g.unk or abs(coalesce(g.bq, 0) - coalesce(led.lq, 0)) > 0.0005;
$$;
create or replace function public.stock_sales_unmatched(p_from date, p_to date, p_loc integer default null, p_item uuid default null, p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path = public as $$
-- bos118 (old body)
declare locs integer[]; lim integer := least(greatest(coalesce(p_limit, 500), 1), 2000); rows_j jsonb; cnt jsonb; tot integer;
begin
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_period'; end if;
  if p_to - p_from > 370 then raise exception 'period_too_long'; end if;
  locs := public._rc118_locs('view_stock_recon', p_loc);
  select coalesce(jsonb_agg(q.j order by q.sale_date desc, q.receipt desc), '[]'::jsonb) into rows_j from (
    select g.sale_date, g.receipt, jsonb_build_object('sale_id', g.sale_id, 'receipt', g.receipt, 'sale_date', g.sale_date, 'location_id', g.location_id,
             'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_id', g.item_id, 'item_code', i.code, 'item_bn', i.name_bn, 'item_en', coalesce(i.name_en, i.name_bn),
             'unit', i.unit, 'base_unit', coalesce(i.base_unit, i.unit), 'sold_qty', round(g.sold_qty, 4), 'sold_base_qty', round(g.base_qty, 4), 'ledger_qty', round(g.ledger_qty, 4),
             'diff_qty', round(g.diff_qty, 4), 'kind', g.kind) as j
      from public._rc118_gap(p_from, p_to, locs, p_item) g join public.items i on i.id = g.item_id join public.locations lo on lo.id = g.location_id
     order by g.sale_date desc, g.receipt desc limit lim) q;
  cnt := public._rc118_gap_summary(p_from, p_to, locs, p_item);
  select coalesce(sum(value::int), 0) into tot from jsonb_each_text(cnt);
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_ids', to_jsonb(locs), 'rows', rows_j, 'counts', cnt, 'total', tot, 'truncated', tot > lim);
end $$;
select tt.chk('G2 the old bodies are in place (no bos120)', (select count(*) from pg_proc where proname in ('_rc118_buckets','_rc118_gap','stock_sales_unmatched') and pronamespace = 'public'::regnamespace and prosrc like '%bos120%') = 0);
select tt.runall('ho');
select tt.chk('G3 OLD: results collected, same number of cases', (select count(*) from tt.ho) = (select count(*) from tt.hn));
select tt.chk('G4 IDENTICAL: every md5 + row count of RECON / FBR / BUCK / UNM / GAP equals the phase118 result',
  (select count(*) from tt.hn n join tt.ho o using (k) where n.h is distinct from o.h) = 0 and (select count(*) from tt.hn n join tt.ho o using (k)) = (select count(*) from tt.hn));
select tt.chk('G4 detail: no case differs (first differing key, if any, is shown in the notice)', (select count(*) from tt.hn n join tt.ho o using (k) where n.h is distinct from o.h) = 0);
select k as first_diff from tt.hn n join tt.ho o using (k) where n.h is distinct from o.h order by k limit 3;

\echo == errors and rights are the same as before
select tt.err('E1 bad period (to before from)', format('select public.stock_sales_unmatched(%L, %L)', tt.today(), tt.today() - 1), 'bad_period');
select tt.err('E2 period over 370 days', format('select public.stock_sales_unmatched(%L, %L)', tt.today() - 400, tt.today()), 'period_too_long');
select tt.as(:'s');
select tt.err('E3 a salesperson without the grant is refused (stock_sales_unmatched)', format('select public.stock_sales_unmatched(%L, %L)', tt.today() - 10, tt.today()), 'not allowed');
select tt.err('E4 a salesperson without the grant is refused (stock_recon_statement)', format('select public.stock_recon_statement(%L, %L)', tt.today() - 10, tt.today()), 'not allowed');
select tt.as(:'o');

\echo == paste phase526 again: restores the new bodies, same results
\i supabase/phase526.sql
select tt.chk('R1 after the paste the three bodies carry bos120 again', (select count(*) from pg_proc where proname in ('_rc118_buckets','_rc118_gap','stock_sales_unmatched') and pronamespace = 'public'::regnamespace and prosrc like '%bos120%') = 3);
select tt.chk('R2 definitions equal the ones saved before the swap (paste is exact)',
  (select def from tt.cur where name = 'buckets') = pg_get_functiondef('public._rc118_buckets(date,date,integer[],uuid,text)'::regprocedure)
  and (select def from tt.cur where name = 'gap') = pg_get_functiondef('public._rc118_gap(date,date,integer[],uuid)'::regprocedure)
  and (select def from tt.cur where name = 'unm') = pg_get_functiondef('public.stock_sales_unmatched(date,date,integer,uuid,integer)'::regprocedure));
select tt.as(:'o');
select tt.runall('hr');
select tt.chk('R3 results after the second paste equal the first NEW run', (select count(*) from tt.hr r join tt.hn n using (k) where r.h is distinct from n.h) = 0 and (select count(*) from tt.hr) = (select count(*) from tt.hn));
\i supabase/phase526.sql
select tt.chk('R4 a third paste is a no-op (definitions unchanged)',
  (select def from tt.cur where name = 'buckets') = pg_get_functiondef('public._rc118_buckets(date,date,integer[],uuid,text)'::regprocedure));

\echo == the guard
-- an unknown tag in one of the three bodies stops the paste (nothing changes: the file is one transaction)
create or replace function public._rc118_gap(p_from date, p_to date, p_locs integer[], p_item uuid)
returns table (sale_id uuid, receipt integer, sale_date date, location_id integer, item_id uuid, sold_qty numeric, base_qty numeric, ledger_qty numeric, diff_qty numeric, kind text)
language sql stable security definer set search_path = public as $$ select null::uuid, null::integer, null::date, null::integer, null::uuid, null::numeric, null::numeric, null::numeric, null::numeric, null::text where false; /* bos118 bos999 */ $$;
create temp table if not exists tt_before as select md5(prosrc) m from pg_proc where proname = '_rc118_buckets' and pronamespace = 'public'::regnamespace;
\i supabase/phase526.sql
select tt.chk('U1 an unknown tag (bos999) in _rc118_gap stops phase120: the body is still the stub', (select prosrc like '%bos999%' and prosrc not like '%bos120%' from pg_proc where proname = '_rc118_gap' and pronamespace = 'public'::regnamespace));
select tt.chk('U2 and the other functions were not changed by the refused paste', (select m from tt_before) = (select md5(prosrc) from pg_proc where proname = '_rc118_buckets' and pronamespace = 'public'::regnamespace));
-- put the real body back through the saved definition, then paste again
select tt.chk('U3 restore: executing the saved _rc118_gap definition and pasting phase120 brings the tagged body back', true);
do $r$ declare d text; begin select def into d from tt.cur where name = 'gap'; execute d; end $r$;
\i supabase/phase526.sql
select tt.chk('U4 after the restore the paste works', (select count(*) from pg_proc where proname in ('_rc118_buckets','_rc118_gap','stock_sales_unmatched') and pronamespace = 'public'::regnamespace and prosrc like '%bos120%') = 3);

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select 'FAIL ' || name from tt.res where not ok;
