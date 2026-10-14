-- REPLACEMENT of phase89g_test.sql for the chain that ends with phase112 + phase113 (batch 1): phase113 re-creates _acct_docs and acct_post_pending, phase112 _r3q_l3_shop_pnl, so a re-pasted phase89 puts back the older text of 11 functions (P2a) and the repair is 103, 105, 109, 110, 111, 112, 113. Same assertions otherwise.
-- (older line:) REPLACEMENT of phase89f_test.sql for the final chain (INT4: ...105..109, 110, 111). Re-pasting 89 changes 9 functions (96/97/99/103/109/110 re-create them); the repair is paste 103, 105, 109, 110, 111 after it. Same assertions otherwise.
-- REPLACEMENT of phase89e_test.sql for a chain that ends with phase105 (Step Sec2): every paste of phase103 is followed by a paste of phase105. Same assertions.
-- FRESH DB ONLY. phase89e_test.sql = phase89d_test.sql for the chain that ends with phase103 (Step E2E): phase89 alone puts back the older text of FIVE functions (P2a lists them) and ONE paste of phase103 repairs all of them (the chain 89, 98, 99 is blocked by the body guard of phase98, which does not know bos103). Phase89d_test.sql itself is NOT edited.
-- Earlier header: phase89d_test.sql = phase89c_test.sql for the chain that ends with phase99 (step Opt): phase99 re-creates online_order_get and online_orders_list, which phase89 also re-asserts, so phase89 alone puts the older text of FOUR functions back (P2a) and the stable end of the re-paste is 89 then 98 then 99 (P2). Everything else is identical to phase89c_test.sql.
-- Original header: Copy of phase89_test.sql for the chain that ends with phase98 (phase89_test P2 'second paste identical' is false by design once phase96/97 exist: 89 alone puts the older _acct_docs back; 89 then 98 is stable). Phase 89 tests (integration fix: final body of every function that more than one phase re-created).
--   Build: phase8 ... phase71, 72 ... 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 90, 91, 89  (docs/PASTE_ORDER.md)
--   (run from the repo root: the P2 block does \i supabase/phase89.sql)  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase89_test.sql | grep -E "FAIL|RESULT"
-- Test data only, no person names. Place 1 only. Numbers are hand-computed above each block.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner') on conflict do nothing;

\echo == T0 every bosNN tag of every phase survives in the final function bodies
with want(fn, tag) as (values
  ('_acct_docs(date)','bos50'),
  ('_acct_docs(date)','bos52'),
  ('_acct_docs(date)','bos72'),
  ('_acct_docs(date)','bos74'),
  ('_acct_docs(date)','bos80'),
  ('_acct_docs(date)','bos85'),
  ('_cogs_lines72(date,date,integer[])','bos80'),
  ('_cogs_lines72(date,date,integer[])','bos88'),
  ('_post_purchase_p13(uuid,jsonb)','bos82'),
  ('_post_purchase_p13(uuid,jsonb)','bos87'),
  ('_r3q_l1_pnl(date,date,integer[],jsonb)','bos72'),
  ('_r3q_l1_pnl(date,date,integer[],jsonb)','bos78'),
  ('_r3q_l3_shop_pnl(date,date,integer[],jsonb)','bos72'),
  ('_r3q_l3_shop_pnl(date,date,integer[],jsonb)','bos78'),
  ('_sale_stock_out()','bos82'),
  ('_sale_stock_out()','bos83'),
  ('_void_purchase_p13(uuid,text)','bos82'),
  ('acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)','bos85'),
  ('acct_post_pending(boolean,integer)','bos72'),
  ('acct_post_pending(boolean,integer)','bos85'),
  ('acct_status()','bos72'),
  ('acct_status()','bos85'),
  ('cost_rule_approve(bigint,text)','bos87'),
  ('dup_suspects(date,date)','bos83'),
  ('inbox_board(integer)','bos86'),
  ('inventory_vs_gl(date,integer)','bos85'),
  ('online_order_get(uuid)','bos76'),
  ('online_order_get(uuid)','bos77'),
  ('online_order_save(uuid,uuid,integer,text,text,text,text,jsonb,text,text,date,numeric,numeric,numeric,text,text,text)','bos80'),
  ('online_orders_list(integer,text,date,date,integer)','bos76'),
  ('online_orders_list(integer,text,date,date,integer)','bos77'),
  ('partner_calculate(bigint,date,date,jsonb)','bos80'),
  ('partner_settlement_save(bigint,date,date,jsonb,text,uuid)','bos80'),
  ('pool_set(integer,date,text,numeric,text,boolean,text,uuid)','bos75'),
  ('production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)','bos72'),
  ('production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)','bos73'),
  ('production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)','bos74'),
  ('production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)','bos80'),
  ('recipe_approve(uuid,text)','bos87'),
  ('recipe_cost(uuid,integer)','bos73'),
  ('recipe_cost(uuid,integer)','bos74'),
  ('sale_return(uuid,uuid,jsonb,text,text,text,text,text)','bos12'),
  ('sale_return(uuid,uuid,jsonb,text,text,text,text,text)','bos80'),
  ('sales_channel_save(integer,text,text,text,text,integer,text,text,boolean)','bos86'),
  ('stock_count_adjust(uuid,integer,numeric,text,text,uuid)','bos85'),
  ('stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid)','bos82'),
  ('stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid)','bos87'),
  ('stock_receive_transfer(uuid,numeric,text)','bos83'),
  ('stock_reconcile(boolean)','bos84'),
  ('urgent_alerts(timestamp with time zone)','bos83'))
select tt.chk('T0 ' || fn || ' carries ' || tag, position(tag in pg_get_functiondef(('public.' || fn)::regprocedure)) > 0) from want;
select tt.chk('T0 the 7-argument acct_journal_post is gone (one function, optional reason)', to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)') is null and to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)') is not null);
select tt.chk('T0 the original Bangla unit message of _sale_stock_out is kept (not re-worded)', position('এককের রূপান্তর জানা নেই, স্টক কমানো হয়নি' in pg_get_functiondef('public._sale_stock_out()'::regprocedure)) > 0);

\echo == setup: items. Water (free, cost 0) 100 kg ; Box item with NO conversion 50 pc ; Rice 10 kg @ 5
insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values
 ('I89-WA','Water','Water','kg','kg',10,true,'finished_good'), ('I89-UB','Boxed','Boxed','box','pc',50,true,'finished_good'), ('I89-RI','Rice','Rice','kg','kg',20,true,'finished_good');
select id as wa from items where code='I89-WA' \gset
select id as ub from items where code='I89-UB' \gset
select id as ri from items where code='I89-RI' \gset
set role authenticated; select tt.as(:'o');
select stock_opening(:'wa'::uuid,1,100,0) is not null as a1 \gset
select stock_opening(:'ub'::uuid,1,50,10) is not null as a2 \gset
select stock_opening(:'ri'::uuid,1,10,5) is not null as a3 \gset
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select set_rule('accounting_on','true') is null as on1 \gset
select item_cost_free_set(:'wa'::uuid, true, 'tap water, no purchase cost') is not null as fr \gset
select tt.chk('setup done', :'a1' and :'a2' and :'a3');
reset role;

\echo == S1 _sale_stock_out keeps phase82 (unit_conv_required) AND phase83 (offline soft stock)
-- default warn = today: sale of 2 boxes of Boxed (no conversion) is accepted, stock unchanged 50, one yellow stock_unit_unknown
insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status)
  values (gen_random_uuid(), 1, 89001, now(), tt.today(), format('[{"item_id":"%s","qty":2,"price":50,"amount":100,"unit":"box"}]', :'ub')::jsonb, 100, 0, 100, 'cash', :'o', 'owner1', 'done') returning id as w1 \gset
select tt.chk('S1 warn (today): accepted, stock stays 50, one yellow stock_unit_unknown', (select qty from stock_balance where item_id=:'ub'::uuid and location_id=1)=50 and (select count(*) from exceptions where sale_id=:'w1'::uuid and flag_code='stock_unit_unknown' and level='yellow')=1);
select set_rule('unit_conv_required','"refuse"') is null as u1 \gset
select tt.err('S1 refuse (phase82 rule): an online sale of the unconverted unit is refused unit_unknown', format($$insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status) values (gen_random_uuid(), 1, 89002, now(), current_date, '[{"item_id":"%s","qty":1,"price":50,"amount":50,"unit":"box"}]'::jsonb, 50, 0, 50, 'cash', '%s', 'owner1', 'done')$$, :'ub', :'o'), 'unit_unknown');
select set_rule('unit_conv_required','"warn"') is null as u2 \gset
-- phase83 rule: a sale replayed from the offline queue may go below stock when offline_soft_stock is ON: Rice 10 kg, sale of 15 kg -> stock -5, one yellow offline_soft_stock
select set_rule('offline_soft_stock','true') is null as o1 \gset
select set_config('bos.offline_replay','1',false);
insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status)
  values (gen_random_uuid(), 1, 89003, now(), tt.today(), format('[{"item_id":"%s","qty":15,"price":20,"amount":300}]', :'ri')::jsonb, 300, 0, 300, 'cash', :'o', 'owner1', 'done') returning id as w3 \gset
select set_config('bos.offline_replay','',false);
select tt.chk('S1 offline soft stock (phase83 rule): accepted, Rice 10 - 15 = -5, one yellow offline_soft_stock', (select qty from stock_balance where item_id=:'ri'::uuid and location_id=1)=-5 and (select count(*) from exceptions where sale_id=:'w3'::uuid and flag_code='offline_soft_stock' and level='yellow')=1);
select set_rule('offline_soft_stock','false') is null as o2 \gset

\echo == S2 free-cost item (phase80) is a KNOWN cost in _acct_docs (with the phase85 stock/card documents) and in _cogs_lines72 (with the phase88 switch)
-- sale of 5 kg Water @ 10 = 50, ledger cost 0, Water marked free
insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status)
  values (gen_random_uuid(), 1, 89004, now(), tt.today(), format('[{"item_id":"%s","qty":5,"price":10,"amount":50}]', :'wa')::jsonb, 50, 0, 50, 'cash', :'o', 'owner1', 'done') returning id as w4 \gset
select tt.chk('S2 _acct_docs: the Water sale has NO cogs_missing flag (bos80 kept by bos85 merge)', exists (select 1 from _acct_docs(tt.today()-5) d where d.source_type='sale' and d.source_id=:'w4' and d.flags is null));
set role authenticated; select tt.as(:'o');
select card_settle(1, tt.today(), 600, 12, 'batch 89', 'aaaaaaaa-0000-0000-0000-000000000089'::uuid) is not null as cs \gset
reset role;
select tt.chk('S2 _acct_docs: the phase85 card settlement document is there as well (Dr bank 588, Dr charges 12, Cr card 600)', exists (select 1 from _acct_docs(tt.today()-5) d where d.source_type='card_settlement'));
select tt.chk('S2 default report cost switch: Water sale COGS 0, led_rev 50, unk_rev 0', (select coalesce(sum(led_cogs),0)=0 and coalesce(sum(led_rev),0)=50 and coalesce(sum(unk_rev),0)=0 and coalesce(sum(fb_rev),0)=0 from _cogs_lines72(tt.today(), tt.today(), array[1]) where item_id=:'wa'::uuid));
set role authenticated; select tt.as(:'o');
select set_rule('report_cost_source','"item_costs"') is null as r1 \gset
reset role;
select tt.chk('S2 switch item_costs (phase88) + free item (phase80): unk_rev 0, led_rev 50 (without bos80 it would be unknown 50)', (select coalesce(sum(unk_rev),0)=0 and coalesce(sum(led_rev),0)=50 from _cogs_lines72(tt.today(), tt.today(), array[1]) where item_id=:'wa'::uuid));
set role authenticated; select tt.as(:'o');
select set_rule('report_cost_source','"ledger_avg"') is null as r2 \gset
reset role;
select tt.chk('S2 switch ledger_avg (phase88) + free item (phase80): unk_rev 0, led_rev 50', (select coalesce(sum(unk_rev),0)=0 and coalesce(sum(led_rev),0)=50 from _cogs_lines72(tt.today(), tt.today(), array[1]) where item_id=:'wa'::uuid));
set role authenticated; select tt.as(:'o');
select set_rule('report_cost_source',null) is null as r3 \gset
select acct_post_pending(false) as pj \gset
reset role;
select tt.chk('S2 posting raises no error; every entry balances', jsonb_array_length(:'pj'::jsonb->'errors') = 0 and (select count(*) from (select entry_id from journal_lines group by entry_id having sum(debit) <> sum(credit)) z) = 0);
select tt.chk('S2 card settlement journalled: bank 588 + charges 12 = card receivable 600', (select coalesce(sum(l.debit),0) from journal_entries e join journal_lines l on l.entry_id=e.id where e.source_type='card_settlement') = 600
  and (select coalesce(sum(l.credit),0) from journal_entries e join journal_lines l on l.entry_id=e.id where e.source_type='card_settlement') = 600);

\echo == P2 paste twice (phase98-aware): re-applying phase89 and then phase98 changes no function body (phase89d: 89, 98, 99)
create temp table h1 as select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f';
\i supabase/phase89.sql
create temp table h2 as select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f';
select tt.chk('P2a phase89 pasted again on the full chain puts back older bodies of exactly 15 functions (phase96/97/99/103/109/110/112/113/114/117 touch them)', (select array_agg(fn order by fn) from h1 full join h2 using (fn) where h1.h is distinct from h2.h) = array['_acct_docs(date)','_cogs_lines72(date,date,integer[])','_post_purchase_p13(uuid,jsonb)','_r3q_l3_shop_pnl(date,date,integer[],jsonb)','_sale_stock_out()','_void_purchase_p13(uuid,text)','acct_post_pending(boolean,integer)','inventory_vs_gl(date,integer)','online_order_get(uuid)','online_orders_list(integer,text,date,date,integer)','pool_set(integer,date,text,numeric,text,boolean,text,uuid)','production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)','recipe_cost(uuid,integer)','sale_return(uuid,uuid,jsonb,text,text,text,text,text)','stock_count_adjust(uuid,integer,numeric,text,text,uuid)']);
\i supabase/phase103.sql
\i supabase/phase105.sql
\i supabase/phase109.sql
\i supabase/phase110.sql
\i supabase/phase111.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase123.sql
create temp table h3 as select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f';
select tt.chk('P2 second paste (89 then 103; phase103 carries the final text of all five, phase98 would refuse over bos103): identical function bodies', (select count(*) from h1 full join h3 using (fn) where h1.h is distinct from h3.h) = 0);

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
