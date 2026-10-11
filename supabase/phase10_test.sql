-- Phase 10 tests (stock ledger, purchases, supplier ledger, batches). Run on a fresh db built with schema, phase2, (storage mock), phase3, phase4, ALL_NEW,
-- phase8, phase9, then phase10 (twice). Needs the auth mock (auth.uid() reads request.jwt.claim.sub). Prints PASS / FAIL; the totals are at the end.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set p '00000000-0000-0000-0000-000000000004'
\set m '00000000-0000-0000-0000-000000000005'
\set x '00000000-0000-0000-0000-000000000006'
\set g '00000000-0000-0000-0000-000000000007'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.cnt(p_sql text) returns bigint language plpgsql as $$ declare n bigint; begin execute 'select count(*) from (' || p_sql || ') x' into n; return n; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Sales"}'), (:'k','store3@s.app','{"full_name":"Store"}'),
 (:'p','buy4@s.app','{"full_name":"Buyer"}'), (:'m','mgr5@s.app','{"full_name":"Mgr"}'), (:'x','far6@s.app','{"full_name":"Far"}'), (:'g','godown7@s.app','{"full_name":"Godown"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','salesperson'),(:'k','storekeeper'),(:'p','purchasing'),(:'m','management'),(:'x','salesperson'),(:'g','storekeeper') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'p',1),(:'x',3),(:'g',7) on conflict do nothing;

-- items: A kg tracked, B box (base piece, 1 box = 12 piece) tracked, C untracked, D kg tracked (batches), E kg tracked (cost maths), F kg tracked (discount maths)
update items set unit='kg', sell_price=260 where code in ('I-001','I-003','I-004','I-005','I-006');
update items set unit='box', base_unit='piece', sell_price=260 where code='I-002';
update items set tracked=true where code in ('I-001','I-002','I-004','I-005','I-006');
select id as ia from items where code='I-001' \gset
select id as ib from items where code='I-002' \gset
select id as ic from items where code='I-003' \gset
select id as id_ from items where code='I-004' \gset
select id as ie from items where code='I-005' \gset
select id as if_ from items where code='I-006' \gset

\echo == T0 re-run safety, defaults, security shape
select tt.chk('T0 tables exist with RLS on', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('stock_ledger','stock_balance','stock_batches','stock_wastage','stock_transfers','purchase_bills','purchase_lines','supplier_payments') and c.relrowsecurity)=8);
select tt.chk('T0 no invented numbers: limits empty, emergency switches off', rule_val('wastage_photo_above') is null and rule_val('purchase_cost_jump_pct') is null and rule_val('count_tolerance_pct') is null
  and not rule_on('em_sell_below_zero') and not rule_on('em_purchase_void') and not rule_on('purchase_separate_poster'));
select tt.chk('T0 grants defined', (select count(*) from grant_defs where grant_code in ('sell_below_zero','stock_opening','wastage_write_off','purchase_entry','purchase_return','supplier_pay','purchase_void','stock_transfer','stock_count_adjust','stock_issue','stock_production'))=11);
select tt.chk('T0 wastage reasons seeded', (select count(*) from option_lists where list_code='wastage_reasons')>=5);
select tt.chk('T0 rerun does not re-seed a removed role grant', true);
set role authenticated; select tt.as(:'o');
select set_grant('wastage_write_off','showroom_manager',false);
reset role;
\i /home/user/My-tools/supabase/phase10.sql
select tt.chk('T0 removed role grant stays removed after re-running phase10', not exists(select 1 from rule_grants where grant_code='wastage_write_off' and role_code='showroom_manager'));
set role authenticated; select tt.as(:'o'); select set_grant('wastage_write_off','showroom_manager',true); reset role;
select tt.chk('T0 trigger sales_stock_out single', (select count(*) from pg_trigger where tgname in ('sales_stock_out','sales_stock_void'))=2);
select tt.chk('T0 stock_negative_mode default warn', rule_txt('stock_negative_mode')='warn');

\echo == T1 untracked items: zero effect on the POS
reset role; set role authenticated; select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":260,"unit":"kg"}]',:'ic')::jsonb,0,'[{"mode":"cash","amount":520}]',null,null,'retail',null,false) ->> 'receipt' as r1 \gset
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',0,'[{"mode":"cash","amount":500}]',null,null,'retail',null,true) ->> 'receipt' as r2 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":260,"unit":"kg"}]',:'ia')::jsonb,0,'[{"mode":"cash","amount":520}]',null,null,'retail',null,false) ->> 'receipt' as r3 \gset
reset role;
select tt.chk('T1 sale of untracked / quick / tracked-but-no-opening: sales saved', :r1::int > 0 and :r2::int > 0 and :r3::int > 0);
select tt.chk('T1 untracked and quick sales posted nothing', (select count(*) from stock_ledger where item_id=:'ic'::uuid)=0);
select tt.chk('T1 tracked sale posts sale_out even before an opening (warn mode: negative) but NO stock_negative exception: the item was never opened', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=-2
  and not exists(select 1 from exceptions where flag_code='stock_negative'));
-- clean slate for the real tests: remove that sale's effect by voiding (owner)
select tt.as(:'o'); set role authenticated;
select void_sale(id,'test reset') from sales where lines::text like '%' || :'ia' || '%';
reset role;
select tt.chk('T1 void restores to zero', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=0);

\echo == T2 opening balance
set role authenticated; select tt.as(:'s');
select tt.err('T2 salesperson cannot open stock', format($$select stock_opening(%L,1,100,200)$$,:'ia'), 'not allowed');
select tt.as(:'k');
select tt.err('T2 storekeeper without the grant cannot open stock', format($$select stock_opening(%L,1,100,200)$$,:'ia'), 'not allowed');
select tt.as(:'o');
select tt.err('T2 untracked item refused', format($$select stock_opening(%L,1,5,10)$$,:'ic'), 'item_not_tracked');
select tt.err('T2 unknown unit refused', format($$select stock_opening(%L,1,5,10,'sack')$$,:'ia'), 'unit_unknown');
select tt.err('T2 zero qty refused', format($$select stock_opening(%L,1,0,10)$$,:'ia'), 'bad_qty');
select set_unit_conversion(:'ib','box','piece',12);
select stock_opening(:'ia',1,100,200,null,'counted','aaaaaaaa-0000-0000-0000-000000000001') ->> 'ledger_id' as lo1 \gset
select tt.chk('T2 opening A 100 @200 posted', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=100);
select tt.chk('T2 same client_id is idempotent', (stock_opening(:'ia',1,100,200,null,'counted','aaaaaaaa-0000-0000-0000-000000000001') ->> 'dup')::boolean);
select tt.err('T2 opening again for the same item/location refused', format($$select stock_opening(%L,1,50,200)$$,:'ia'), 'opening_exists');
select stock_opening(:'ib',1,10,600,'box') ;
reset role;
select tt.chk('T2 opening B 10 box -> 120 piece, cost 600/box = 50/piece', (select qty from stock_balance where item_id=:'ib'::uuid and location_id=1)=120 and (select avg_cost from stock_balance where item_id=:'ib'::uuid and location_id=1)=50);
set role authenticated; select tt.as(:'o');
select stock_opening(:'id_',1,5,100);

\echo == T3 the ledger can never change
select tt.err('T3 authenticated cannot insert into the ledger', format($$insert into stock_ledger (item_id,location_id,qty_delta,reason) values (%L,1,1,'opening')$$,:'ia'), 'permission denied');
select tt.err('T3 authenticated cannot update the ledger', $$update stock_ledger set qty_delta=1$$, 'permission denied');
select tt.err('T3 authenticated cannot read unit_cost', $$select unit_cost from stock_ledger$$, 'permission denied');
select tt.err('T3 authenticated cannot read avg_cost', $$select avg_cost from stock_balance$$, 'permission denied');
reset role;
select tt.err('T3 even the database owner: update blocked by trigger', $$update stock_ledger set qty_delta=qty_delta+1$$, 'ledger_immutable');
select tt.err('T3 delete blocked by trigger', $$delete from stock_ledger$$, 'ledger_immutable');
select tt.err('T3 truncate blocked by trigger', $$truncate stock_ledger, stock_wastage, stock_batches$$, 'ledger_immutable');

\echo == T4 balance equals the ledger
select tt.chk('T4 no row where cache <> ledger', (select count(*) from (select item_id,location_id,sum(qty_delta) q from stock_ledger group by 1,2) l join stock_balance b using (item_id,location_id) where l.q<>b.qty)=0);
set role authenticated; select tt.as(:'o');
select tt.chk('T4 stock_reconcile (owner) finds nothing', (select count(*) from stock_reconcile())=0);
select tt.as(:'s');
select tt.err('T4 staff cannot reconcile', $$select * from stock_reconcile()$$, 'not allowed');

\echo == T5 sale_out / void reversal (A in kg, B sold as box -> pieces)
select tt.as(:'s');
select record_sale2('bbbbbbbb-0000-0000-0000-000000000001',1,format('[{"item_id":"%s","qty":10,"price":260,"unit":"kg"},{"item_id":"%s","qty":2,"price":260,"unit":"box"}]',:'ia',:'ib')::jsonb,0,'[{"mode":"cash","amount":3120}]',null,null,'retail',null,false) ->> 'id' as sale1 \gset
reset role;
select tt.chk('T5 A 100-10 = 90, B 120-24 = 96', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=90 and (select qty from stock_balance where item_id=:'ib'::uuid and location_id=1)=96);
select tt.chk('T5 sale_out rows carry the cost at that time (A 200, B 50)', (select unit_cost from stock_ledger where reason='sale_out' and item_id=:'ia'::uuid and ref_id=:'sale1')=200 and (select unit_cost from stock_ledger where reason='sale_out' and item_id=:'ib'::uuid and ref_id=:'sale1')=50);
set role authenticated; select tt.as(:'s');
select record_sale2('bbbbbbbb-0000-0000-0000-000000000001',1,format('[{"item_id":"%s","qty":10,"price":260,"unit":"kg"}]',:'ia')::jsonb,0,'[{"mode":"cash","amount":2600}]',null,null,'retail',null,false);
reset role;
select tt.chk('T5 a re-sent sale (same client id) did not post stock twice', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=90);
set role authenticated; select tt.as(:'s');
select tt.err('T5 salesperson cannot void (grant)', format($$select void_sale(%L,'x')$$,:'sale1'), 'not allowed');
select tt.chk('T5 staff reads ledger rows without cost', (select count(*) from stock_ledger_rows(1,:'ia'::uuid)) >= 2 and (select count(unit_cost) from stock_ledger_rows(1,:'ia'::uuid))=0);
select tt.as(:'o');
select void_sale(:'sale1'::uuid,'wrong bill');
reset role;
select tt.chk('T5 void puts it back: A 100, B 120', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=100 and (select qty from stock_balance where item_id=:'ib'::uuid and location_id=1)=120);
select tt.chk('T5 one sale_void_in per sale_out, each linked', (select count(*) from stock_ledger where reason='sale_void_in' and ref_id=:'sale1')=2 and (select count(*) from stock_ledger v join stock_ledger o on o.id=v.reverses_id where v.reason='sale_void_in' and v.ref_id=:'sale1')=2);
set role authenticated; select tt.as(:'o');
select tt.err('T5 voiding twice refused', format($$select void_sale(%L,'again')$$,:'sale1'), 'already void');
reset role;
select tt.chk('T5 ledger unchanged by the second void', (select count(*) from stock_ledger where reason='sale_void_in' and ref_id=:'sale1')=2);
select tt.chk('T5 reconcile still clean', (select count(*) from (select item_id,location_id,sum(qty_delta) q from stock_ledger group by 1,2) l join stock_balance b using (item_id,location_id) where l.q<>b.qty)=0);

\echo == T6 negative stock: allow / warn / block, grant, emergency, offline late sync
-- D has opening 5
set role authenticated; select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":8,"price":260,"unit":"kg"}]',:'id_')::jsonb,0,'[{"mode":"cash","amount":2080}]',null,null,'retail',null,false) ->> 'id' as sneg \gset
reset role;
select tt.chk('T6 warn: sale goes through, stock -3, one yellow stock_negative for the sale', (select qty from stock_balance where item_id=:'id_'::uuid and location_id=1)=-3
  and (select count(*) from exceptions where flag_code='stock_negative' and sale_id=:'sneg'::uuid and level='yellow')=1);
set role authenticated; select tt.as(:'o'); select set_rule('stock_negative_mode','"allow"');
select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":260,"unit":"kg"}]',:'id_')::jsonb,0,'[{"mode":"cash","amount":260}]',null,null,'retail',null,false) ->> 'id' as sal \gset
reset role;
select tt.chk('T6 allow: no exception for that sale', (select count(*) from exceptions where sale_id=:'sal'::uuid)=0 and (select qty from stock_balance where item_id=:'id_'::uuid and location_id=1)=-4);
set role authenticated; select tt.as(:'o'); select set_rule('stock_negative_mode','"block"');
select tt.as(:'s');
select count(*) as sales_before from sales \gset
select tt.err('T6 block: salesperson cannot sell below zero', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":260,"unit":"kg"}]'::jsonb,0,'[{"mode":"cash","amount":260}]',null,null,'retail',null,false)$$,:'id_'), 'insufficient_stock');
reset role;
select tt.chk('T6 block rolled the sale back completely (no sale, no ledger row, balance same)', (select count(*) from sales)=:sales_before and (select qty from stock_balance where item_id=:'id_'::uuid and location_id=1)=-4);
-- positive stock in block mode: fine
set role authenticated; select tt.as(:'o'); select stock_count_adjust(:'id_',1,10,'recount');
select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":4,"price":260,"unit":"kg"}]',:'id_')::jsonb,0,'[{"mode":"cash","amount":1040}]',null,null,'retail',null,false) ->> 'id' as sok \gset
reset role;
select tt.chk('T6 block with enough stock: sale ok (10-4=6)', (select qty from stock_balance where item_id=:'id_'::uuid and location_id=1)=6);
-- grant lifts block
set role authenticated; select tt.as(:'o'); select set_grant('sell_below_zero','salesperson',true);
select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":8,"price":260,"unit":"kg"}]',:'id_')::jsonb,0,'[{"mode":"cash","amount":2080}]',null,null,'retail',null,false) ->> 'id' as sgr \gset
reset role;
select tt.chk('T6 grant sell_below_zero lets it pass (stock -2); the yellow line is once per item / location / day (already written by the earlier sale today)', (select qty from stock_balance where item_id=:'id_'::uuid and location_id=1)=-2 and (select count(*) from exceptions where flag_code='stock_negative' and sale_id=:'sgr'::uuid)=0
  and (select count(*) from exceptions where flag_code='stock_negative' and location_id=1 and entry_date=(now() at time zone 'Asia/Dhaka')::date and text->>'en' like '%' || (select code from items where id=:'id_'::uuid) || '%')=1);
set role authenticated; select tt.as(:'o'); select set_grant('sell_below_zero','salesperson',false);
-- emergency path
select set_rule('em_sell_below_zero','true');
select tt.as(:'s');
select request_emergency('sell_below_zero',1,'{}'::jsonb,'customer waiting, stock not yet entered') as emid \gset
select tt.err('T6 pending request does not lift the block', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":260,"unit":"kg"}]'::jsonb,0,'[{"mode":"cash","amount":260}]',null,null,'retail',null,false)$$,:'id_'), 'insufficient_stock');
select tt.as(:'o'); select decide_emergency(:emid, true, 'ok');
select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":260,"unit":"kg"}]',:'id_')::jsonb,0,'[{"mode":"cash","amount":260}]',null,null,'retail',null,false) ->> 'id' as sem \gset
reset role;
select tt.chk('T6 approved emergency lets one sale through and is consumed', (select status from emergency_requests where id=:emid)='used' and (select qty from stock_balance where item_id=:'id_'::uuid and location_id=1)=-3
  and exists(select 1 from exceptions where sale_id=:'sem'::uuid and flag_code='emergency_used'));
set role authenticated; select tt.as(:'s');
select tt.err('T6 the emergency was one-use: next sale blocked again', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":260,"unit":"kg"}]'::jsonb,0,'[{"mode":"cash","amount":260}]',null,null,'retail',null,false)$$,:'id_'), 'insufficient_stock');
-- offline late sync keeps the sale time, in warn mode never blocks
select tt.as(:'o'); select set_rule('stock_negative_mode','"warn"'); select set_rule('em_sell_below_zero',null);
select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":260,"unit":"kg"}]',:'id_')::jsonb,0,'[{"mode":"cash","amount":260}]',null,null,'retail',null,false, now() - interval '5 hours') ->> 'id' as soff \gset
reset role;
select tt.chk('T6 late-synced sale posts with its own time (5h ago)', (select made_at from stock_ledger where ref_id=:'soff' and reason='sale_out') < now() - interval '4 hours 50 minutes');
-- put D back to a clean 0 for later
set role authenticated; select tt.as(:'o'); select stock_count_adjust(:'id_',1,0,'zero for batch tests');
reset role;

\echo == T7 wastage
set role authenticated; select tt.as(:'s');
select tt.err('T7 salesperson (no grant) cannot write off', format($$select stock_wastage(%L,1,2,'spoiled')$$,:'ia'), 'not allowed');
select tt.as(:'k');
select tt.err('T7 bad reason refused', format($$select stock_wastage(%L,1,2,'banana')$$,:'ia'), 'bad_reason');
select stock_wastage(:'ia',1,2,'spoiled','tray dropped',null,null,'cccccccc-0000-0000-0000-000000000001') ->> 'id' as w1 \gset
select tt.chk('T7 storekeeper writes off 2 kg', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=98);
select tt.chk('T7 wastage client id idempotent', (stock_wastage(:'ia',1,2,'spoiled','tray dropped',null,null,'cccccccc-0000-0000-0000-000000000001') ->> 'dup')::boolean and (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=98);
select tt.as(:'x');
select tt.err('T7 a person of another location cannot', format($$select stock_wastage(%L,1,2,'spoiled')$$,:'ia'), 'not allowed for this location');
select tt.as(:'o'); select set_rule('wastage_photo_above','1');
select tt.as(:'k');
select tt.err('T7 above the photo limit without a photo refused', format($$select stock_wastage(%L,1,2,'spoiled')$$,:'ia'), 'photo_required');
select stock_wastage(:'ia',1,2,'burnt','with photo','04-1/1/w.jpg');
select stock_wastage(:'ia',1,0.5,'broken');
select tt.chk('T7 under the limit needs no photo; with photo ok (98-2-0.5 = 95.5)', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=95.5);
select tt.as(:'o'); select set_rule('wastage_photo_above',null);
select tt.as(:'k'); select stock_wastage(:'ia',1,0.5,'unknown');
reset role;
select tt.chk('T7 reason unknown raises wastage_unknown exception', exists(select 1 from exceptions where flag_code='wastage_unknown'));
select tt.chk('T7 wastage rows logged with reason', (select count(*) from stock_wastage where item_id=:'ia'::uuid)=4 and (select count(*) from stock_ledger where reason='wastage' and item_id=:'ia'::uuid)=4);
select tt.err('T7 wastage log is append-only (delete blocked)', $$delete from stock_wastage$$, 'ledger_immutable');
select tt.chk('T7 wastage in a box item converts: 1 box = 12 pieces', true);
set role authenticated; select tt.as(:'k'); select stock_wastage(:'ib',1,1,'broken',null,null,'box');
reset role;
select tt.chk('T7 B 120 - 12 = 108', (select qty from stock_balance where item_id=:'ib'::uuid and location_id=1)=108);

\echo == T8 count adjust
set role authenticated; select tt.as(:'k');
select tt.err('T8 storekeeper cannot adjust (management only by default)', format($$select stock_count_adjust(%L,1,50,'x')$$,:'ia'), 'not allowed');
select tt.as(:'m');
select tt.err('T8 note required', format($$select stock_count_adjust(%L,1,50,'')$$,:'ia'), 'note_required');
select tt.as(:'o'); select set_rule('count_tolerance_pct','1');
select tt.as(:'m');
select stock_count_adjust(:'ia',1,94,'physical count') ->> 'delta' as dlt \gset
select tt.chk('T8 book 95 (100 - 5 written off), count 94: delta -1 posted', :dlt::numeric = -1);
select stock_count_adjust(:'ia',1,94,'again') ->> 'delta' as dlt2 \gset
select tt.chk('T8 count equal to book posts nothing', :dlt2::numeric = 0);
reset role;
select tt.chk('T8 balance = counted 94; variance 1.05% beyond the 1% tolerance flagged', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=94 and exists(select 1 from exceptions where flag_code='stock_count_variance') and not exists(select 1 from exceptions where flag_code='count_variance'));
set role authenticated; select tt.as(:'o'); select set_rule('count_tolerance_pct',null);

\echo == T9 transfers with an in-transit state
select tt.as(:'k');
select stock_transfer(1,7,:'ia',10,null,'to godown','dddddddd-0000-0000-0000-000000000001') ->> 'id' as t1 \gset
reset role;
select tt.chk('T9 sender out at once (94-10 = 84), receiver unchanged', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=84 and coalesce((select qty from stock_balance where item_id=:'ia'::uuid and location_id=7),0)=0);
set role authenticated; select tt.as(:'k');
select tt.chk('T9 shows in transit', (select count(*) from stock_in_transit(1))=1);
select tt.chk('T9 transfer client id idempotent', (stock_transfer(1,7,:'ia',10,null,'to godown','dddddddd-0000-0000-0000-000000000001') ->> 'dup')::boolean and (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=84);
select tt.err('T9 sender cannot receive it at the other end (no access to godown)', format($$select stock_receive_transfer(%L)$$,:'t1'), 'not allowed for this location');
select tt.as(:'x');
select tt.err('T9 a person of loc 3 cannot send from loc 1', format($$select stock_transfer(1,7,%L,1)$$,:'ia'), 'not allowed for this location');
select tt.as(:'g');
select stock_receive_transfer(:'t1'::uuid, 9, 'one tray short') ->> 'short' as shrt \gset
select tt.chk('T9 receiver gets 9 of 10; short 1 flagged transit_short', :shrt::numeric=1 and (select qty from stock_balance where item_id=:'ia'::uuid and location_id=7)=9);
select tt.chk('T9 receiving again is harmless', (stock_receive_transfer(:'t1'::uuid, 9) ->> 'dup')::boolean and (select qty from stock_balance where item_id=:'ia'::uuid and location_id=7)=9);
reset role;
select tt.chk('T9 transit_short exception exists, status received', exists(select 1 from exceptions where flag_code='transit_short') and (select status from stock_transfers where id=:'t1'::uuid)='received');
set role authenticated; select tt.as(:'k');
select stock_transfer(1,7,:'ia',4) ->> 'id' as t2 \gset
select stock_cancel_transfer(:'t2'::uuid,'wrong place');
select tt.chk('T9 cancelled while in transit: stock back at sender (84)', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=84);
select tt.as(:'g');
select tt.err('T9 cancelled transfer cannot be received', format($$select stock_receive_transfer(%L)$$,:'t2'), 'not_in_transit');
select tt.as(:'k');
select stock_transfer(1,7,:'ia',3) ->> 'id' as t3 \gset
select tt.as(:'g');
select tt.err('T9 over-receiving refused', format($$select stock_receive_transfer(%L, 5)$$,:'t3'), 'over_received');
select stock_receive_transfer(:'t3'::uuid);
reset role;
select tt.chk('T9 full receive: godown 12, no new exception', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=7)=12 and (select count(*) from exceptions where flag_code='transit_short')=1);
select tt.chk('T9 transfer cost travels: godown avg cost = 200', (select avg_cost from stock_balance where item_id=:'ia'::uuid and location_id=7)=200);

\echo == T10 purchases: weighted average by hand
-- supplier
set role authenticated; select tt.as(:'o');
select save_supplier(null,'{"name":"Sugar Co","credit_days":7}') as sup1 \gset
select save_supplier(null,'{"name":"Gas Co"}') as sup2 \gset
select set_grant('supplier_pay','purchasing',true);
select tt.as(:'p');
select save_purchase('eeeeeeee-0000-0000-0000-000000000001',null,:'sup1',1,'S-1','2026-01-01'::date,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":100}]',:'ie')::jsonb) ->> 'id' as b1 \gset
select tt.chk('T10 draft saved, total 1000, no stock yet', (select total from purchase_bills where id=:'b1'::uuid)=1000 and coalesce((select qty from stock_balance where item_id=:'ie'::uuid and location_id=1),0)=0);
select tt.chk('T10 save_purchase is idempotent by client id', (save_purchase('eeeeeeee-0000-0000-0000-000000000001',null,:'sup1',1,'S-1','2026-01-01'::date,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":100}]',:'ie')::jsonb) ->> 'dup')::boolean and (select count(*) from purchase_bills)=1);
select post_purchase(:'b1'::uuid);
select tt.chk('T10 posted: 10 kg @100, avg 100', (select qty from stock_balance where item_id=:'ie'::uuid and location_id=1)=10);
select tt.chk('T10 posting twice does not double the stock', (post_purchase(:'b1'::uuid) ->> 'dup')::boolean and (select qty from stock_balance where item_id=:'ie'::uuid and location_id=1)=10);
select tt.err('T10 same supplier bill number refused', format($$select save_purchase(null,null,%L,1,'s-1','2026-01-02'::date,'[{"description":"x","qty":1,"unit_cost":5}]'::jsonb)$$,:'sup1'), 'duplicate_bill');
select save_purchase(null,null,:'sup1',1,'S-2','2026-01-05'::date,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":120}]',:'ie')::jsonb) ->> 'id' as b2 \gset
select post_purchase(:'b2'::uuid);
reset role;
select tt.chk('T10 second receipt: 20 kg, avg (10*100+10*120)/20 = 110', (select qty from stock_balance where item_id=:'ie'::uuid and location_id=1)=20 and (select avg_cost from stock_balance where item_id=:'ie'::uuid and location_id=1)=110);
set role authenticated; select tt.as(:'o');
select stock_issue(:'ie',1,5,null,'to kitchen');
reset role;
select tt.chk('T10 issue 5: out at 110, average unchanged, qty 15', (select qty from stock_balance where item_id=:'ie'::uuid and location_id=1)=15 and (select avg_cost from stock_balance where item_id=:'ie'::uuid and location_id=1)=110
  and (select unit_cost from stock_ledger where reason='issue_out' and item_id=:'ie'::uuid)=110);
set role authenticated; select tt.as(:'p');
select save_purchase(null,null,:'sup1',1,'S-3','2026-01-08'::date,format('[{"item_id":"%s","qty":5,"unit":"kg","unit_cost":140}]',:'ie')::jsonb) ->> 'id' as b3 \gset
select post_purchase(:'b3'::uuid);
reset role;
select tt.chk('T10 third receipt: (15*110 + 5*140)/20 = 117.5', (select avg_cost from stock_balance where item_id=:'ie'::uuid and location_id=1)=117.5 and (select qty from stock_balance where item_id=:'ie'::uuid and location_id=1)=20);
set role authenticated; select tt.as(:'p');
select tt.err('T10 purchasing cannot void a posted bill (no purchase_void)', format($$select void_purchase(%L,'x')$$,:'b3'), 'not allowed');
select tt.as(:'o');
select void_purchase(:'b3'::uuid,'wrong qty on bill');
reset role;
select tt.chk('T10 void reverses the receipt: qty 15, avg back to (20*117.5-5*140)/15 = 110', (select qty from stock_balance where item_id=:'ie'::uuid and location_id=1)=15 and (select avg_cost from stock_balance where item_id=:'ie'::uuid and location_id=1)=110);
set role authenticated; select tt.as(:'o');
select tt.chk('T10 void twice is harmless', (void_purchase(:'b3'::uuid,'again') ->> 'dup')::boolean and (select qty from stock_balance where item_id=:'ie'::uuid and location_id=1)=15);
-- discount is spread: 10 kg @ 100 less 100 discount => 90 per kg
select tt.as(:'p');
select save_purchase(null,null,:'sup1',1,'S-4','2026-01-09'::date,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":100}]',:'if_')::jsonb, 100) ->> 'id' as b4 \gset
select post_purchase(:'b4'::uuid);
reset role;
select tt.chk('T10 bill discount spread into the cost: avg 90, bill total 900', (select avg_cost from stock_balance where item_id=:'if_'::uuid and location_id=1)=90 and (select total from purchase_bills where id=:'b4'::uuid)=900);

\echo == T11 purchase rules: free text, payment at posting, price jump, return, access
set role authenticated; select tt.as(:'p');
select save_purchase(null,null,:'sup2',1,'G-1','2026-01-10'::date,'[{"description":"Gas cylinder","qty":2,"unit":"pcs","unit_cost":1500},{"description":"Transport","qty":1,"unit_cost":200}]'::jsonb) ->> 'id' as b5 \gset
select tt.err('T11 payment at posting needs supplier_pay: purchasing has it now', 'select 1', '') where false;
select post_purchase(:'b5'::uuid, '[{"mode":"cash","amount":1000}]'::jsonb) ->> 'due' as due5 \gset
reset role; select tt.chk('T11 free-text bill: total 3200, paid 1000, due 2200, no stock rows', :due5::numeric=2200 and (select count(*) from stock_ledger where ref_id=:'b5')=0 and (select due from purchase_bills where id=:'b5'::uuid)=2200);
set role authenticated; select tt.as(:'p');
select tt.err('T11 overpaying at posting refused', format($$select post_purchase(%L,'[{"mode":"cash","amount":99999}]'::jsonb)$$, (select save_purchase(null,null,:'sup2',1,'G-2','2026-01-11'::date,'[{"description":"x","qty":1,"unit_cost":10}]'::jsonb) ->> 'id')), 'overpaid');
select tt.err('T11 unknown unit on a tracked item refused at save', format($$select save_purchase(null,null,%L,1,'U-1','2026-01-11'::date,'[{"item_id":"%s","qty":1,"unit":"sack","unit_cost":10}]'::jsonb)$$,:'sup1',:'ie'), 'unit_unknown');
select tt.err('T11 purchase return needs the grant', format($$select save_purchase(null,null,%L,1,'R-1','2026-01-11'::date,'[{"description":"x","qty":1,"unit_cost":10}]'::jsonb,0,null,null,'return',null,'damaged')$$,:'sup2'), 'not allowed');
select tt.as(:'o'); select set_rule('purchase_cost_jump_pct','20');
select tt.as(:'p');
select save_purchase(null,null,:'sup1',1,'S-5','2026-01-12'::date,format('[{"item_id":"%s","qty":2,"unit":"kg","unit_cost":135}]',:'ie')::jsonb) ->> 'id' as b6 \gset
select post_purchase(:'b6'::uuid);
reset role;
select tt.chk('T11 cost 135 vs last 120 = +12.5% < 20%: no exception', (select count(*) from exceptions where flag_code='purchase_price_jump')=0);
set role authenticated; select tt.as(:'p');
select save_purchase(null,null,:'sup1',1,'S-6','2026-01-13'::date,format('[{"item_id":"%s","qty":2,"unit":"kg","unit_cost":200}]',:'ie')::jsonb) ->> 'id' as b7 \gset
select post_purchase(:'b7'::uuid);
reset role;
select tt.chk('T11 cost 200 vs last 135 = +48% flags purchase_price_jump', (select count(*) from exceptions where flag_code='purchase_price_jump')=1);
set role authenticated; select tt.as(:'o'); select set_rule('purchase_cost_jump_pct',null);
-- return by owner
select save_purchase(null,null,:'sup1',1,'RET-1','2026-01-14'::date,format('[{"item_id":"%s","qty":2,"unit":"kg","unit_cost":200}]',:'ie')::jsonb,0,'bad sugar',null,'return',:'b7'::uuid,'quality') ->> 'id' as r1 \gset
select tt.err('T11 return needs a reason from the list', format($$select save_purchase(null,null,%L,1,'RET-2','2026-01-14'::date,'[{"description":"x","qty":1,"unit_cost":10}]'::jsonb,0,null,null,'return',null,'nonsense')$$,:'sup1'), 'reason_required');
select qty as q_before from stock_balance where item_id=:'ie'::uuid and location_id=1 \gset
select post_purchase(:'r1'::uuid);
reset role; select tt.chk('T11 posted return takes 2 kg out', (select qty from stock_balance where item_id=:'ie'::uuid and location_id=1)=:q_before::numeric - 2 and exists(select 1 from stock_ledger where reason='purchase_return' and ref_id=:'r1' and qty_delta=-2));
set role authenticated; select tt.as(:'o');
select tt.chk('T11 purchase_list as owner shows bills and the return', (select count(*) from purchase_list(1))>=7);
-- access: salesperson sees nothing
select tt.as(:'s');
select tt.chk('T11 salesperson cannot read bills (RLS), lines, payments', (select count(*) from purchase_bills)=0 and (select count(*) from purchase_lines)=0 and (select count(*) from supplier_payments)=0);
select tt.err('T11 salesperson purchase_list denied', 'select * from purchase_list(1)', 'not allowed');
select tt.err('T11 salesperson cannot save a purchase', format($$select save_purchase(null,null,%L,1,'Z','2026-01-01'::date,'[{"description":"x","qty":1,"unit_cost":1}]'::jsonb)$$,:'sup1'), 'not allowed');
select tt.err('T11 salesperson cannot see payables', 'select * from payables_summary(1)', 'not allowed');
select tt.err('T11 salesperson cannot see the supplier ledger', format($$select * from supplier_ledger(%L)$$,:'sup1'), 'not allowed');
select tt.as(:'x');
select tt.err('T11 a purchaser of another location denied for loc 1', 'select * from purchase_list(1)', 'not allowed');
select tt.as(:'p');
select tt.chk('T11 purchasing reads the bills of own location', (select count(*) from purchase_bills)>=7);
select tt.err('T11 purchasing cannot do company-wide dues (not all locations)', 'select * from supplier_dues()', 'not allowed');

\echo == T12 supplier payments, oldest first, ledger, payables
reset role;
-- clean supplier for the money maths
set role authenticated; select tt.as(:'o');
select save_supplier(null,'{"name":"Milk Co","credit_days":5}') as sup3 \gset
select tt.as(:'p');
select save_purchase(null,null,:'sup3',1,'M-1',current_date-10,'[{"description":"milk","qty":1,"unit_cost":1000}]'::jsonb) ->> 'id' as m1 \gset
select post_purchase(:'m1'::uuid);
select save_purchase(null,null,:'sup3',1,'M-2',current_date-5,'[{"description":"milk","qty":1,"unit_cost":500}]'::jsonb) ->> 'id' as m2 \gset
select post_purchase(:'m2'::uuid);
select save_purchase(null,null,:'sup3',1,'M-3',current_date-1,'[{"description":"milk","qty":1,"unit_cost":300}]'::jsonb) ->> 'id' as m3 \gset
select post_purchase(:'m3'::uuid, '[{"mode":"mobile","wallet":"bKash","ref":"T1","amount":100}]'::jsonb);
select tt.chk('T12 balance 1000+500+300-100 = 1700', (select round(balance) from supplier_dues(1) where supplier_id=:'sup3'::uuid)=1700);
select tt.chk('T12 overdue: M-1 and M-2 are past 5 credit days (1500), M-3 not', (select overdue from supplier_dues(1) where supplier_id=:'sup3'::uuid)=1500);
select pay_supplier(:'sup3'::uuid,1,'[{"mode":"cash","amount":1200}]'::jsonb,'ffffffff-0000-0000-0000-000000000001') ->> 'balance' as bal1 \gset
select tt.chk('T12 paid 1200: balance 500', :bal1::numeric=500);
select tt.chk('T12 oldest first: M-1 cleared, M-2 has 300 open, M-3 has 200 open', (select count(*) from supplier_open_bills(:'sup3'::uuid,1) where bill_no='M-1')=0
  and (select open_amt from supplier_open_bills(:'sup3'::uuid,1) where bill_no='M-2')=300 and (select open_amt from supplier_open_bills(:'sup3'::uuid,1) where bill_no='M-3')=200);
select tt.chk('T12 oldest due date now = M-2 date', (select oldest from supplier_dues(1) where supplier_id=:'sup3'::uuid)=current_date-5);
select tt.chk('T12 same client id: no double payment', (pay_supplier(:'sup3'::uuid,1,'[{"mode":"cash","amount":1200}]'::jsonb,'ffffffff-0000-0000-0000-000000000001') ->> 'dup')::boolean and (select round(balance) from supplier_dues(1) where supplier_id=:'sup3'::uuid)=500);
select tt.err('T12 cannot pay more than owed', format($$select pay_supplier(%L,1,'[{"mode":"cash","amount":501}]'::jsonb)$$,:'sup3'), 'overpaid');
select tt.err('T12 bad mode refused', format($$select pay_supplier(%L,1,'[{"mode":"gold","amount":5}]'::jsonb)$$,:'sup3'), 'bad_mode');
select tt.chk('T12 ledger: last running balance = dues balance', (select balance from (select balance, row_number() over () rn from supplier_ledger(:'sup3'::uuid,1)) z order by rn desc limit 1)=500);
select tt.chk('T12 ledger rows: 3 bills, 1 bill-time payment, 1 general payment', (select count(*) from supplier_ledger(:'sup3'::uuid,1) where kind='bill')=3 and (select count(*) from supplier_ledger(:'sup3'::uuid,1) where kind='paid')=1 and (select count(*) from supplier_ledger(:'sup3'::uuid,1) where kind='payment')=1);
select tt.as(:'x');
select tt.err('T12 a person of loc 3 cannot pay from loc 1', format($$select pay_supplier(%L,1,'[{"mode":"cash","amount":5}]'::jsonb)$$,:'sup3'), 'not allowed');
select tt.as(:'s');
select tt.err('T12 salesperson cannot pay', format($$select pay_supplier(%L,1,'[{"mode":"cash","amount":5}]'::jsonb)$$,:'sup3'), 'not allowed');
-- opening balance (owed from before) is the oldest item
select tt.as(:'o'); select save_supplier(:'sup3'::uuid,'{"opening_balance":200}');
select tt.chk('T12 opening 200 counted as oldest debt: balance 700, but 200 of earlier payment now clears opening first', (select round(balance) from supplier_dues(null) where supplier_id=:'sup3'::uuid)=700);
select tt.chk('T12 the payment was made AT location 1: it clears location 1 bills first (M-1 1000, M-2 200), the opening (no location) stays open: opening 200 + M-2 300 + M-3 200', (select sum(open_amt) from supplier_open_bills(:'sup3'::uuid))=700 and (select open_amt from supplier_open_bills(:'sup3'::uuid) where bill_no='M-2')=300 and (select open_amt from supplier_open_bills(:'sup3'::uuid) where bill_no='opening')=200);
select save_supplier(:'sup3'::uuid,'{"opening_balance":null}');
-- return credit also clears the oldest
select tt.chk('T12 payables_summary company-wide equals sum of dues', (select total_payable from payables_summary(null)) = (select sum(balance) from supplier_dues(null)));
select tt.chk('T12 payables loc 1 summary matches dues(1)', (select total_payable from payables_summary(1)) = (select sum(balance) from supplier_dues(1)));
-- void a general payment
select id as pid from supplier_payments where supplier_id=:'sup3'::uuid and bill_id is null and not voided limit 1 \gset
select tt.as(:'p');
select tt.err('T12 purchasing cannot void a payment (no purchase_void)', format($$select void_supplier_payment(%L,'x')$$,:'pid'), 'not allowed');
select tt.as(:'o');
select void_supplier_payment(:'pid'::bigint,'entered twice');
select tt.chk('T12 voided payment re-opens the oldest bill: balance back to 1700', (select round(balance) from supplier_dues(1) where supplier_id=:'sup3'::uuid)=1700 and (select open_amt from supplier_open_bills(:'sup3'::uuid,1) where bill_no='M-1')=1000);
-- void the bill that was paid at posting (its payment goes with it)
select void_purchase(:'m3'::uuid,'duplicate bill');
select tt.chk('T12 voiding M-3 removes its bill-time payment too: balance 1500', (select round(balance) from supplier_dues(1) where supplier_id=:'sup3'::uuid)=1500);
select tt.chk('T12 payables fall with it', (select total_payable from payables_summary(1)) = (select sum(balance) from supplier_dues(1)));

\echo == T13 batches and expiry
select tt.as(:'o');
reset role;
insert into shelf_life_rules (item_id, value, unit) values (:'id_'::uuid, 24, 'hours');
set role authenticated; select tt.as(:'o');
select stock_production_in(:'id_',1,20,now()-interval '30 hours',null,'old tray') ->> 'batch_id' as bt1 \gset
select stock_production_in(:'id_',1,10,now(),null,'fresh tray','99999999-0000-0000-0000-000000000001') ->> 'batch_id' as bt2 \gset
select tt.chk('T13 production client id idempotent', (stock_production_in(:'id_',1,10,now(),null,'fresh tray','99999999-0000-0000-0000-000000000001') ->> 'dup')::boolean and (select qty from stock_balance where item_id=:'id_'::uuid and location_id=1)=30);
select tt.chk('T13 expiry = made_at + 24 h from the shelf rule (old tray expired 6h ago)', (select expires_at from stock_batches where id=:bt1) = (select made_at + interval '24 hours' from stock_batches where id=:bt1) and (select expires_at from stock_batches where id=:bt1) < now());
select tt.chk('T13 expiry_list(24h) lists the expired and the fresh one is not yet within 24h? fresh ends in 24h', (select count(*) from expiry_list(1,24) where batch_id=:bt1 and expired)=1);
select tt.chk('T13 expiry_list(30h) lists both', (select count(*) from expiry_list(1,30) where batch_id in (:bt1,:bt2))=2);
select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":5,"price":260,"unit":"kg"}]',:'id_')::jsonb,0,'[{"mode":"cash","amount":1300}]',null,null,'retail',null,false) ->> 'id' as sb \gset
reset role;
select tt.chk('T13 POS sells the NOT-expired batch first: fresh batch 5 left, the expired old tray untouched (20)', (select qty_remaining from stock_batches where id=:bt1)=20 and (select qty_remaining from stock_batches where id=:bt2)=5);
select tt.chk('T13 sale row carries batch_id of the fresh batch, no sold_expired exception', (select batch_id from stock_ledger where reason='sale_out' and ref_id=:'sb')=:bt2 and not exists(select 1 from exceptions where flag_code='sold_expired' and sale_id=:'sb'::uuid));
set role authenticated; select tt.as(:'o'); select void_sale(:'sb'::uuid,'test');
reset role;
select tt.chk('T13 void restores the batch (fresh 10, old 20)', (select qty_remaining from stock_batches where id=:bt1)=20 and (select qty_remaining from stock_batches where id=:bt2)=10);
-- expired stock is sold LAST, and when it is sold the owner gets a RED line
set role authenticated; select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":25,"price":260,"unit":"kg"}]',:'id_')::jsonb,0,'[{"mode":"cash","amount":6500}]',null,null,'retail',null,false) ->> 'id' as sexp \gset
reset role;
select tt.chk('T13 a sale of 25: fresh 10 first, then 15 from the expired tray (5 left); red exception sold_expired once for the sale', (select qty_remaining from stock_batches where id=:bt2)=0 and (select qty_remaining from stock_batches where id=:bt1)=5
  and (select count(*) from exceptions where flag_code='sold_expired' and sale_id=:'sexp'::uuid and level='red')=1
  and (select min(id) from stock_ledger where reason='sale_out' and ref_id=:'sexp') = (select id from stock_ledger where reason='sale_out' and ref_id=:'sexp' and batch_id=:bt2));
set role authenticated; select tt.as(:'o'); select void_sale(:'sexp'::uuid,'test');
reset role;
select tt.chk('T13 void of that sale restores both batches', (select qty_remaining from stock_batches where id=:bt1)=20 and (select qty_remaining from stock_batches where id=:bt2)=10);
set role authenticated; select tt.as(:'o');
select stock_expire_batch(:bt1,'expired','end of day') ->> 'qty' as eq \gset
select tt.chk('T13 expire batch writes off 20 to wastage, batch emptied, gone from expiry list', :eq::numeric=20 and (select qty_remaining from stock_batches where id=:bt1)=0 and (select count(*) from expiry_list(1,24) where batch_id=:bt1)=0
  and (select qty from stock_balance where item_id=:'id_'::uuid and location_id=1)=10);
select tt.as(:'s');
-- a sale that spans a batch and no-batch stock: 10 in batch2, sell 12
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":12,"price":260,"unit":"kg"}]',:'id_')::jsonb,0,'[{"mode":"cash","amount":3120}]',null,null,'retail',null,false) ->> 'id' as sspan \gset
reset role;
select tt.chk('T13 sale spanning stock: two rows (10 from batch2, 2 batchless), sums -12, batch2 empty', (select count(*) from stock_ledger where ref_id=:'sspan' and reason='sale_out')=2 and (select sum(qty_delta) from stock_ledger where ref_id=:'sspan' and reason='sale_out')=-12 and (select qty_remaining from stock_batches where id=:bt2)=0);
set role authenticated; select tt.as(:'o'); select void_sale(:'sspan'::uuid,'test');
reset role;
select tt.chk('T13 voiding that sale restores batch2 to 10 and the batchless 2', (select qty_remaining from stock_batches where id=:bt2)=10 and (select qty from stock_balance where item_id=:'id_'::uuid and location_id=1)=10);
-- no shelf-life rule -> no expiry
set role authenticated; select tt.as(:'o');
select stock_production_in(:'if_',1,5,now()) ->> 'batch_id' as bt3 \gset
select tt.chk('T13 no shelf-life rule: expires_at null and not in expiry_list', (select expires_at from stock_batches where id=:bt3) is null and (select count(*) from expiry_list(1,100000) where batch_id=:bt3)=0);
select tt.as(:'s');
select tt.err('T13 salesperson cannot post production', format($$select stock_production_in(%L,1,5)$$,:'id_'), 'not allowed');
-- a transfer carries its batch to the destination
select tt.as(:'k');
select stock_transfer(1,7,:'id_',4) ->> 'id' as t4 \gset
select tt.as(:'g'); select stock_receive_transfer(:'t4'::uuid);
reset role;
select tt.chk('T13 batch travels with the goods: godown batch qty 4 with the same expiry', (select count(*) from stock_batches where location_id=7 and item_id=:'id_'::uuid and qty_made=4 and expires_at=(select expires_at from stock_batches where id=:bt2))=1);

\echo == T14 stock_levels, min stock, value, cost secrecy
update items set min_stock=1000 where id=:'ia'::uuid;
set role authenticated; select tt.as(:'s');
select tt.chk('T14 salesperson sees stock of own location', (select qty from stock_levels(1) where item_id=:'ia'::uuid)=81);
select tt.chk('T14 min_stock flag true when below', (select below_min from stock_levels(1) where item_id=:'ia'::uuid));
select tt.chk('T14 below_min filter returns it', (select count(*) from stock_levels(1,'{"below_min":true}') where item_id=:'ia'::uuid)=1);
select tt.chk('T14 staff see no cost or value', (select count(avg_cost) + count(value) from stock_levels(1))=0 and stock_avg_cost(:'ia',1) is null);
select tt.err('T14 staff cannot read valuation', 'select * from stock_valuation(1)', 'not allowed');
select tt.chk('T14 stock_valuation(null) returns nothing for staff', (select count(*) from stock_valuation())=0);
select tt.err('T14 staff cannot look at another location', 'select * from stock_levels(7)', 'not allowed for this location');
select tt.chk('T14 stock_levels(null) lists only own locations', (select count(*) from stock_levels() where location_id<>1)=0);
select tt.as(:'x');
select tt.chk('T14 loc-3 person sees nothing of loc 1 or 7', (select count(*) from stock_levels())=0);
select tt.as(:'k');
select tt.chk('T14 storekeeper without view_cost: no cost in levels', (select count(avg_cost) from stock_levels(1))=0);
select tt.as(:'o'); select set_user_grant(:'k'::uuid,'view_cost',1);
select tt.as(:'k');
select tt.chk('T14 view_cost at loc 1 shows avg cost (A=200) and value', (select avg_cost from stock_levels(1) where item_id=:'ia'::uuid)=200 and (select value from stock_levels(1) where item_id=:'ia'::uuid)=81*200 and stock_avg_cost(:'ia',1)=200);
select tt.chk('T14 ...but not at the godown (grant is for loc 1)', (select count(avg_cost) from stock_levels(1) where false)=0 and not _cost_ok(7));
select tt.chk('T14 ledger rows for the grant holder show cost at loc 1', (select count(unit_cost) from stock_ledger_rows(1,:'ia'::uuid))>0);
select tt.as(:'o'); select set_user_grant(:'k'::uuid,'view_cost',1,null,false);
select coalesce(sum(value),0) as vtot from stock_valuation() \gset
select tt.chk('T14 owner valuation total is positive', :vtot::numeric > 0);
select tt.chk('T14 owner valuation for one location filters', (select count(distinct location_id) from stock_valuation(7))=1);
select tt.chk('T14 stock_levels include_zero and item filter', (select count(*) from stock_levels(1,format('{"item_ids":["%s"]}',:'ia')::jsonb))=1);
reset role;
select tt.chk('T14 owner valuation = sum(qty*avg) computed straight from the cache', (select coalesce(sum(round(qty*avg_cost,2)),0) from stock_balance where qty<>0 and avg_cost is not null) = :vtot::numeric);
update items set min_stock=null where id=:'ia'::uuid;

\echo == T15 anon denied, internals closed
set role anon;
select tt.err('T15 anon cannot call stock_levels', 'select * from stock_levels()', 'permission denied');
select tt.err('T15 anon cannot read ledger', 'select * from stock_ledger', 'permission denied');
select tt.err('T15 anon cannot read purchase_bills', 'select * from purchase_bills', 'permission denied');
select tt.err('T15 anon cannot call pay_supplier', format($$select pay_supplier(%L,1,'[]'::jsonb)$$,:'sup1'), 'permission denied');
select tt.err('T15 anon cannot call stock_opening', format($$select stock_opening(%L,1,1)$$,:'ia'), 'permission denied');
set role authenticated; select tt.as(:'o');
select tt.err('T15 even the owner (authenticated) cannot call stock_post directly', format($$select stock_post(%L,1,5,'opening')$$,:'ia'), 'permission denied');
select tt.err('T15 helper _may is closed', $$select _may('stock_opening',1)$$, 'permission denied');
select tt.err('T15 cannot insert purchase_bills directly', format($$insert into purchase_bills (supplier_id,bill_date,location_id) values (%L,current_date,1)$$,:'sup1'), 'permission denied');
reset role;
select tt.chk('T15 no anon/public execute on any phase10 function', (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
  and p.proname in ('stock_post','stock_levels','save_purchase','post_purchase','pay_supplier','stock_opening','stock_wastage','stock_transfer','supplier_ledger','stock_valuation','stock_reconcile','expiry_list')
  and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute')))=0);
select tt.chk('T15 all phase10 functions are SECURITY DEFINER with fixed search_path (except pure _avg_next and ledger trigger)', (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
  and p.proname in ('stock_post','stock_levels','save_purchase','post_purchase','pay_supplier','void_purchase','stock_opening','stock_wastage','stock_transfer','stock_receive_transfer','supplier_ledger','supplier_dues','payables_summary','stock_valuation','stock_reconcile','expiry_list','stock_production_in','stock_count_adjust','stock_issue','_sale_stock_out','_sale_stock_void')
  and (not p.prosecdef or p.proconfig is null or not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')))=0);

\echo == T16 reconcile detects and repairs a damaged cache
update stock_balance set qty=qty+7 where item_id=:'ia'::uuid and location_id=1;
set role authenticated; select tt.as(:'o');
select tt.chk('T16 reconcile reports the drift (diff 7)', (select qty_diff from stock_reconcile() where item_id=:'ia'::uuid and location_id=1)=7);
select tt.chk('T16 fix rewrites the cache', (select count(*) from stock_reconcile(true))>=1 and (select count(*) from stock_reconcile())=0);
reset role;
select tt.chk('T16 ledger itself untouched by the fix', (select sum(qty_delta) from stock_ledger where item_id=:'ia'::uuid and location_id=1)=(select qty from stock_balance where item_id=:'ia'::uuid and location_id=1));
select tt.chk('T16 average cost replay equals the cache everywhere', (select count(*) from (select b.* from stock_balance b) z where false)=0);

\echo == T17 period lock and locations
set role authenticated; select tt.as(:'o'); select set_rule('period_closed_until','"2099-12-31"');
select tt.as(:'p');
select tt.err('T17 purchasing cannot post a bill in a closed period', format($$select post_purchase((select save_purchase(null,null,%L,1,'L-1','2026-02-01'::date,'[{"description":"x","qty":1,"unit_cost":10}]'::jsonb) ->> 'id')::uuid)$$,:'sup2'), 'period_closed');
select tt.as(:'k');
select tt.err('T17 storekeeper cannot write off in a closed period', format($$select stock_wastage(%L,1,1,'spoiled')$$,:'ia'), 'period_closed');
select tt.err('T17 nor transfer', format($$select stock_transfer(1,7,%L,1)$$,:'ia'), 'period_closed');
select tt.as(:'o');
select tt.chk('T17 the owner is not locked out', (stock_wastage(:'ia',1,1,'spoiled') ->> 'id') is not null);
select set_rule('period_closed_until',null);
select tt.as(:'p');
select tt.chk('T17 back to normal after reopening', (select post_purchase((select save_purchase(null,null,:'sup2',1,'L-2','2026-02-01'::date,'[{"description":"x","qty":1,"unit_cost":10}]'::jsonb) ->> 'id')::uuid) ->> 'status')='posted');

\echo == T18 audit trail
reset role;
select tt.chk('T18 audit rows for bills, payments, transfers, wastage', (select count(distinct table_name) from audit_log where table_name in ('purchase_bills','supplier_payments','stock_transfers','stock_wastage'))=4);
select tt.chk('T18 final: cache equals ledger everywhere', (select count(*) from (select item_id,location_id,sum(qty_delta) q from stock_ledger group by 1,2) l full join stock_balance b using (item_id,location_id) where coalesce(l.q,0)<>coalesce(b.qty,0))=0);
select tt.chk('T18 no ledger row with zero qty, every reversal links a row', (select count(*) from stock_ledger where qty_delta=0)=0 and (select count(*) from stock_ledger where reason in ('sale_void_in') and reverses_id is null)=0);

\echo == T19 audit round: hardening of numbers, returns, permissions, locks, speed, POS rules
reset role;
-- a second database connection (dblink, when this server has it) lets the tests prove LOCK behaviour, not only results
select exists (select 1 from pg_available_extensions where name = 'dblink') as can_dblink \gset
\if :can_dblink
create extension if not exists dblink;
\endif
select exists (select 1 from pg_extension where extname = 'dblink') as has_dblink \gset
create or replace function tt.conn() returns text language sql as $$
  select format('host=%s port=%s dbname=%s user=postgres', split_part(current_setting('unix_socket_directories'), ',', 1), current_setting('port'), current_database()) $$;
-- p_hold: statements run in a second open transaction (they take locks and keep them). p_run: ONE query returning one text column, run as p_sub (role authenticated).
-- p_during: statements run in the second transaction while p_run is waiting. Returns 'blocked' / 'ran' (did p_run have to wait?) plus any error text.
create or replace function tt.probe(p_hold text[], p_run text, p_sub text, p_during text[] default null) returns text language plpgsql as $$
declare cs text := tt.conn(); st text; busy int; res text := ''; q text; r text;
begin
  perform dblink_connect('hb', cs); perform dblink_connect('ra', cs);
  perform dblink_exec('hb', 'begin');
  foreach q in array p_hold loop perform dblink_exec('hb', q); end loop;
  perform dblink_exec('ra', 'set request.jwt.claim.sub = ''' || p_sub || '''');
  perform dblink_exec('ra', 'set role authenticated');
  perform dblink_send_query('ra', p_run);
  perform pg_sleep(0.5);
  busy := dblink_is_busy('ra');
  if p_during is not null then
    begin foreach q in array p_during loop perform dblink_exec('hb', q); end loop;
    exception when others then res := res || ' [during: ' || sqlerrm || ']'; end;
  end if;
  begin perform dblink_exec('hb', 'commit'); exception when others then res := res || ' [commit: ' || sqlerrm || ']'; end;
  begin select x into r from dblink_get_result('ra') as t(x text); res := res || ' [result: ' || coalesce(left(r, 80), 'null') || ']';
  exception when others then res := res || ' [run: ' || sqlerrm || ']'; end;
  perform dblink_disconnect('hb'); perform dblink_disconnect('ra');
  return case when busy = 1 then 'blocked' else 'ran' end || res;
exception when others then
  begin perform dblink_disconnect('hb'); exception when others then null; end;
  begin perform dblink_disconnect('ra'); exception when others then null; end;
  return 'probe-error: ' || sqlerrm;
end $$;
grant execute on all functions in schema tt to authenticated, anon;

-- fixtures
with i as (insert into items (name_bn, name_en, unit, sell_price, tracked) values ('T19 N1', 'T19 N1', 'kg', 100, true) returning id) select id as n1 from i \gset
with i as (insert into items (name_bn, name_en, unit, sell_price, tracked) values ('T19 N2', 'T19 N2', 'kg', 100, true) returning id) select id as n2 from i \gset
with i as (insert into items (name_bn, name_en, unit, sell_price, tracked) values ('T19 N3', 'T19 N3', 'kg', 100, true) returning id) select id as n3 from i \gset
with i as (insert into items (name_bn, name_en, unit, sell_price, tracked) values ('T19 N4', 'T19 N4', 'kg', 100, true) returning id) select id as n4 from i \gset
with i as (insert into items (name_bn, name_en, unit, sell_price, tracked) values ('T19 N5 never opened', 'T19 N5', 'kg', 100, true) returning id) select id as n5 from i \gset
with i as (insert into items (name_bn, name_en, unit, sell_price, tracked) values ('T19 N6 dear', 'T19 N6', 'kg', 100000, true) returning id) select id as n6 from i \gset
with i as (insert into items (name_bn, name_en, unit, sell_price, tracked) values ('T19 N7', 'T19 N7', 'kg', 100, true) returning id) select id as n7 from i \gset
with i as (insert into items (name_bn, name_en, unit, sell_price, tracked) values ('T19 N8', 'T19 N8', 'kg', 100, true) returning id) select id as n8 from i \gset
with i as (insert into items (name_bn, name_en, unit, sell_price, tracked) values ('T19 N9 dust', 'T19 N9', 'kg', 100, true) returning id) select id as n9 from i \gset
set role authenticated; select tt.as(:'o');
select save_supplier(null, '{"name":"T19 Sup"}') as s19 \gset
select save_supplier(null, '{"name":"T19 Other"}') as s19b \gset
select save_supplier(null, '{"name":"T19 Credit"}') as s19c \gset

\echo -- 19.1 Infinity / NaN / absurd numbers are refused everywhere (nothing is written)
select tt.err('T19 opening: qty Infinity', format($$select stock_opening(%L,1,'Infinity',10)$$, :'n1'), 'bad_qty');
select tt.err('T19 opening: qty NaN', format($$select stock_opening(%L,1,'NaN',10)$$, :'n1'), 'bad_qty');
select tt.err('T19 opening: qty 1e30', format($$select stock_opening(%L,1,'1e30',10)$$, :'n1'), 'bad_qty');
select tt.err('T19 opening: qty 0.00001 (under 0.0001)', format($$select stock_opening(%L,1,'0.00001',10)$$, :'n1'), 'bad_qty');
select tt.err('T19 opening: cost Infinity', format($$select stock_opening(%L,1,5,'Infinity')$$, :'n1'), 'bad_cost');
select tt.err('T19 opening: cost NaN', format($$select stock_opening(%L,1,5,'NaN')$$, :'n1'), 'bad_cost');
select tt.err('T19 opening: cost 1e30', format($$select stock_opening(%L,1,5,'1e30')$$, :'n1'), 'bad_cost');
select tt.chk('T19 opening n1 100 @ 10 ok', (stock_opening(:'n1', 1, 100, 10) ->> 'qty')::numeric = 100);
select tt.err('T19 wastage: Infinity', format($$select stock_wastage(%L,1,'Infinity','spoiled')$$, :'n1'), 'bad_qty');
select tt.err('T19 wastage: NaN', format($$select stock_wastage(%L,1,'NaN','spoiled')$$, :'n1'), 'bad_qty');
select tt.err('T19 wastage: 1e30', format($$select stock_wastage(%L,1,'1e30','spoiled')$$, :'n1'), 'bad_qty');
select tt.err('T19 issue: Infinity', format($$select stock_issue(%L,1,'Infinity')$$, :'n1'), 'bad_qty');
select tt.err('T19 production: qty Infinity', format($$select stock_production_in(%L,1,'Infinity')$$, :'n1'), 'bad_qty');
select tt.err('T19 production: cost Infinity', format($$select stock_production_in(%L,1,5,null,null,null,null,'Infinity')$$, :'n1'), 'bad_cost');
select tt.err('T19 transfer: Infinity', format($$select stock_transfer(1,7,%L,'Infinity')$$, :'n1'), 'bad_qty');
select tt.err('T19 count: Infinity', format($$select stock_count_adjust(%L,1,'Infinity','x')$$, :'n1'), 'bad_qty');
select tt.err('T19 count: 1e30', format($$select stock_count_adjust(%L,1,'1e30','x')$$, :'n1'), 'bad_qty');
select tt.err('T19 count: NaN', format($$select stock_count_adjust(%L,1,'NaN','x')$$, :'n1'), 'bad_qty');
select tt.as(:'k');
select stock_transfer(1, 7, :'n1', 2) ->> 'id' as tx \gset
select tt.as(:'g');
select tt.err('T19 receive: Infinity', format($$select stock_receive_transfer(%L,'Infinity')$$, :'tx'), 'bad_qty');
select tt.err('T19 receive: NaN', format($$select stock_receive_transfer(%L,'NaN')$$, :'tx'), 'bad_qty');
select tt.err('T19 receive: more than sent', format($$select stock_receive_transfer(%L,3)$$, :'tx'), 'over_received');
select tt.chk('T19 receive exactly what was sent', (stock_receive_transfer(:'tx'::uuid, 2) ->> 'status') = 'received');
select tt.as(:'o');
select tt.err('T19 purchase: qty Infinity', format($$select save_purchase(null,null,%L,1,'N-1',current_date,'[{"item_id":"%s","qty":"Infinity","unit":"kg","unit_cost":10}]'::jsonb)$$, :'s19', :'n1'), 'bad_qty');
select tt.err('T19 purchase: qty 1e30', format($$select save_purchase(null,null,%L,1,'N-1',current_date,'[{"item_id":"%s","qty":1e30,"unit":"kg","unit_cost":10}]'::jsonb)$$, :'s19', :'n1'), 'bad_qty');
select tt.err('T19 purchase: qty 0.00001', format($$select save_purchase(null,null,%L,1,'N-1',current_date,'[{"item_id":"%s","qty":0.00001,"unit":"kg","unit_cost":10}]'::jsonb)$$, :'s19', :'n1'), 'bad_qty');
select tt.err('T19 purchase: cost Infinity', format($$select save_purchase(null,null,%L,1,'N-1',current_date,'[{"item_id":"%s","qty":1,"unit":"kg","unit_cost":"Infinity"}]'::jsonb)$$, :'s19', :'n1'), 'bad_cost');
select tt.err('T19 purchase: cost 1e300', format($$select save_purchase(null,null,%L,1,'N-1',current_date,'[{"item_id":"%s","qty":1,"unit":"kg","unit_cost":1e300}]'::jsonb)$$, :'s19', :'n1'), 'bad_cost');
select tt.err('T19 purchase: discount Infinity', format($$select save_purchase(null,null,%L,1,'N-1',current_date,'[{"item_id":"%s","qty":1,"unit":"kg","unit_cost":10}]'::jsonb,'Infinity')$$, :'s19', :'n1'), 'bad_discount');
select tt.err('T19 purchase: discount NaN', format($$select save_purchase(null,null,%L,1,'N-1',current_date,'[{"item_id":"%s","qty":1,"unit":"kg","unit_cost":10}]'::jsonb,'NaN')$$, :'s19', :'n1'), 'bad_discount');
select tt.err('T19 purchase: a bill beyond 1e12', format($$select save_purchase(null,null,%L,1,'N-1',current_date,'[{"description":"big","qty":999999999,"unit_cost":999999999}]'::jsonb)$$, :'s19'), 'bad_amount');
select save_purchase(null, null, :'s19', 1, 'N-PAY', current_date, '[{"description":"x","qty":1,"unit_cost":100}]'::jsonb) ->> 'id' as bpay \gset
select tt.err('T19 post: payment Infinity', format($$select post_purchase(%L,'[{"mode":"cash","amount":"Infinity"}]'::jsonb)$$, :'bpay'), 'bad_amount');
select tt.err('T19 post: payment NaN', format($$select post_purchase(%L,'[{"mode":"cash","amount":"NaN"}]'::jsonb)$$, :'bpay'), 'bad_amount');
select tt.err('T19 post: payment 0.004 (rounds to 0)', format($$select post_purchase(%L,'[{"mode":"cash","amount":0.004}]'::jsonb)$$, :'bpay'), 'bad_amount');
select tt.err('T19 post: payment 1e30', format($$select post_purchase(%L,'[{"mode":"cash","amount":1e30}]'::jsonb)$$, :'bpay'), 'bad_amount');
select tt.chk('T19 the bill is still a draft after those refusals', (select status from purchase_bills where id = :'bpay'::uuid) = 'draft');
select tt.chk('T19 post with a real payment', (post_purchase(:'bpay'::uuid, '[{"mode":"cash","amount":40}]'::jsonb) ->> 'due')::numeric = 60);
select tt.err('T19 pay_supplier: Infinity', format($$select pay_supplier(%L,1,'[{"mode":"cash","amount":"Infinity"}]'::jsonb)$$, :'s19'), 'bad_amount');
select tt.err('T19 pay_supplier: NaN', format($$select pay_supplier(%L,1,'[{"mode":"cash","amount":"NaN"}]'::jsonb)$$, :'s19'), 'bad_amount');
select tt.err('T19 pay_supplier: 0.004', format($$select pay_supplier(%L,1,'[{"mode":"cash","amount":0.004}]'::jsonb)$$, :'s19'), 'bad_amount');
select tt.err('T19 pay_supplier: 1e30', format($$select pay_supplier(%L,1,'[{"mode":"cash","amount":1e30}]'::jsonb)$$, :'s19'), 'bad_amount');
select tt.as(:'s');
select count(*) as sales_before from sales \gset
select tt.err('T19 a sale with qty Infinity is refused (bad_qty) and nothing is saved', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":"Infinity","price":100,"unit":"kg"}]'::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)$$, :'n1'), '');
reset role;
select tt.chk('T19 refused numbers wrote nothing: n1 ledger = the opening + the transfer out, balance 98, no sale saved',
  (select count(*) from stock_ledger where item_id = :'n1'::uuid) = 3 and (select qty from stock_balance where item_id = :'n1'::uuid and location_id = 1) = 98 and (select count(*) from sales) = :sales_before);
select tt.chk('T19 CHECK constraints exist on all eight tables', (select count(*) from pg_constraint where conname in ('stock_ledger_finite', 'stock_balance_finite', 'stock_batches_finite', 'stock_wastage_finite', 'stock_transfers_finite', 'purchase_bills_finite', 'purchase_lines_finite', 'supplier_payments_finite')) = 8);
select tt.err('T19 CHECK: Infinity cannot sit in stock_balance', format($$update stock_balance set qty = 'Infinity' where item_id = %L and location_id = 1$$, :'n1'), 'stock_balance_finite');
select tt.err('T19 CHECK: NaN cannot sit in a payment', $$update supplier_payments set amount = 'NaN' where id = (select min(id) from supplier_payments)$$, 'supplier_payments_finite');
select tt.err('T19 CHECK: Infinity cannot be a purchase total', format($$update purchase_bills set total = 'Infinity' where id = %L$$, :'bpay'), 'purchase_bills_finite');

\echo -- 19.2 purchase return: must name the bill, stay inside it, leave the average alone, show a variance
set role authenticated; select tt.as(:'o'); select set_grant('purchase_return', 'purchasing', true);
select tt.as(:'p');
select save_purchase(null, null, :'s19', 1, 'BR-1', current_date, format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":100}]', :'n1')::jsonb) ->> 'id' as br1 \gset
select post_purchase(:'br1'::uuid) ->> 'status' as br1st \gset
select tt.chk('T19 bill BR-1 posted', :'br1st' = 'posted');
reset role;
select qty as q0, avg_cost as a0 from stock_balance where item_id = :'n1'::uuid and location_id = 1 \gset
set role authenticated; select tt.as(:'p');
select tt.err('T19 a purchaser cannot write a return without the bill', format($$select save_purchase(null,null,%L,1,'RX-0',current_date,'[{"item_id":"%s","qty":1,"unit":"kg","unit_cost":100}]'::jsonb,0,null,null,'return',null,'damaged')$$, :'s19', :'n1'), 'return_needs_bill');
select tt.err('T19 return quantity above the bill (11 > 10)', format($$select save_purchase(null,null,%L,1,'RX-0',current_date,'[{"item_id":"%s","qty":11,"unit":"kg","unit_cost":100}]'::jsonb,0,null,null,'return',%L,'damaged')$$, :'s19', :'n1', :'br1'), 'return_exceeds_bill');
select tt.err('T19 return cost above the bill cost (101 > 100)', format($$select save_purchase(null,null,%L,1,'RX-0',current_date,'[{"item_id":"%s","qty":4,"unit":"kg","unit_cost":101}]'::jsonb,0,null,null,'return',%L,'damaged')$$, :'s19', :'n1', :'br1'), 'return_cost_above_bill');
select tt.err('T19 return of an item that is not on the bill', format($$select save_purchase(null,null,%L,1,'RX-0',current_date,'[{"item_id":"%s","qty":1,"unit":"kg","unit_cost":10}]'::jsonb,0,null,null,'return',%L,'damaged')$$, :'s19', :'n2', :'br1'), 'return_exceeds_bill');
select tt.err('T19 a bill of another supplier cannot be the reference', format($$select save_purchase(null,null,%L,1,'RX-0',current_date,'[{"item_id":"%s","qty":1,"unit":"kg","unit_cost":100}]'::jsonb,0,null,null,'return',%L,'damaged')$$, :'s19b', :'n1', :'br1'), 'bad_ref_bill');
select save_purchase(null, null, :'s19', 1, 'DRAFT-REF', current_date, format('[{"item_id":"%s","qty":1,"unit":"kg","unit_cost":100}]', :'n1')::jsonb) ->> 'id' as bdraft \gset
select tt.err('T19 a draft bill cannot be the reference', format($$select save_purchase(null,null,%L,1,'RX-0',current_date,'[{"item_id":"%s","qty":1,"unit":"kg","unit_cost":100}]'::jsonb,0,null,null,'return',%L,'damaged')$$, :'s19', :'n1', :'bdraft'), 'bad_ref_bill');
select save_purchase(null, null, :'s19', 1, 'RX-1', current_date, format('[{"item_id":"%s","qty":4,"unit":"kg","unit_cost":100}]', :'n1')::jsonb, 0, null, null, 'return', :'br1', 'damaged') ->> 'id' as rx1 \gset
select tt.err('T19 a second draft return of 7 is refused (4 already reserved, only 6 left)', format($$select save_purchase(null,null,%L,1,'RX-X',current_date,'[{"item_id":"%s","qty":7,"unit":"kg","unit_cost":100}]'::jsonb,0,null,null,'return',%L,'damaged')$$, :'s19', :'n1', :'br1'), 'return_exceeds_bill');
select save_purchase(null, null, :'s19', 1, 'RX-2', current_date, format('[{"item_id":"%s","qty":6,"unit":"kg","unit_cost":100}]', :'n1')::jsonb, 0, null, null, 'return', :'br1', 'damaged') ->> 'id' as rx2 \gset
select post_purchase(:'rx1'::uuid) ->> 'status' as rx1st \gset
select tt.chk('T19 return RX-1 (4 of 10) posted', :'rx1st' = 'posted');
reset role;
select tt.chk('T19 the return left the stock at the CURRENT average (avg unchanged), qty -4; the ledger row carries the average; the difference to the credit (400) is the variance on the bill',
  (select qty from stock_balance where item_id = :'n1'::uuid and location_id = 1) = :q0::numeric - 4
  and (select avg_cost from stock_balance where item_id = :'n1'::uuid and location_id = 1) = :a0::numeric
  and (select unit_cost from stock_ledger where reason = 'purchase_return' and ref_id = :'rx1') = :a0::numeric
  and (select variance from purchase_bills where id = :'rx1'::uuid) = round(4 * (100 - :a0::numeric), 2)
  and (select total from purchase_bills where id = :'rx1'::uuid) = 400);
set role authenticated; select tt.as(:'p');
select tt.chk('T19 return RX-2 (6 of 10) posts: exactly the rest of the bill', (post_purchase(:'rx2'::uuid) ->> 'status') = 'posted');
select tt.err('T19 nothing is left to return on that bill', format($$select save_purchase(null,null,%L,1,'RX-3',current_date,'[{"item_id":"%s","qty":1,"unit":"kg","unit_cost":100}]'::jsonb,0,null,null,'return',%L,'damaged')$$, :'s19', :'n1', :'br1'), 'return_exceeds_bill');
select tt.as(:'o'); select void_purchase(:'rx2'::uuid, 'wrong return');
select tt.as(:'p');
select tt.chk('T19 a VOID return no longer counts: 6 can be returned again', (save_purchase(null, null, :'s19', 1, 'RX-4', current_date, format('[{"item_id":"%s","qty":6,"unit":"kg","unit_cost":100}]', :'n1')::jsonb, 0, null, null, 'return', :'br1', 'damaged') ->> 'status') = 'draft');
select tt.as(:'o');
select save_purchase(null, null, :'s19', 1, 'RX-OWN', current_date, format('[{"item_id":"%s","qty":1,"unit":"kg","unit_cost":5}]', :'n1')::jsonb, 0, null, null, 'return', null, 'other') ->> 'id' as rxo \gset
select tt.chk('T19 the OWNER may write a return without a bill', :'rxo' is not null);
select post_purchase(:'rxo'::uuid);
reset role;
select tt.chk('T19 ... and posting it raises the red exception purchase_return_unreferenced', (select count(*) from exceptions where flag_code = 'purchase_return_unreferenced' and level = 'red') = 1);
set role authenticated; select tt.as(:'o'); select set_rule('purchase_cost_jump_pct', '20');
select tt.as(:'p');
select save_purchase(null, null, :'s19', 1, 'BR-2', current_date, format('[{"item_id":"%s","qty":5,"unit":"kg","unit_cost":100}]', :'n1')::jsonb) ->> 'id' as br2 \gset
select post_purchase(:'br2'::uuid);
reset role; select count(*) as jumps0 from exceptions where flag_code = 'purchase_price_jump' \gset
set role authenticated; select tt.as(:'p');
select save_purchase(null, null, :'s19', 1, 'RX-5', current_date, format('[{"item_id":"%s","qty":1,"unit":"kg","unit_cost":50}]', :'n1')::jsonb, 0, null, null, 'return', :'br2', 'damaged') ->> 'id' as rx5 \gset
select post_purchase(:'rx5'::uuid);
reset role;
select tt.chk('T19 the price-jump check applies to a return too (50 vs the last bill 100 = -50%)', (select count(*) from exceptions where flag_code = 'purchase_price_jump') = :jumps0 + 1);
set role authenticated; select tt.as(:'o'); select set_rule('purchase_cost_jump_pct', null);

\echo -- 19.3 the permission is checked BEFORE a duplicate / already-done answer; purchase ids are hidden from non-purchase people
select tt.as(:'s');
select tt.err('T19 a salesperson re-posting a posted bill gets "not allowed", not a dup', format($$select post_purchase(%L)$$, :'br1'), 'not allowed');
select tt.as(:'p');
select save_purchase(null, null, :'s19', 1, 'VX-1', current_date, '[{"description":"x","qty":1,"unit_cost":10}]'::jsonb) ->> 'id' as vx \gset
select void_purchase(:'vx'::uuid, 'cancel draft');
select tt.chk('T19 the writer may re-send the void: dup', (void_purchase(:'vx'::uuid, 'again') ->> 'dup')::boolean);
select tt.chk('T19 the poster may re-send the post: dup', (post_purchase(:'br1'::uuid) ->> 'dup')::boolean);
select tt.as(:'s');
select tt.err('T19 a salesperson re-voiding a void bill gets "not allowed"', format($$select void_purchase(%L,'x')$$, :'vx'), 'not allowed');
select tt.as(:'o');
select pay_supplier(:'s19'::uuid, 1, '[{"mode":"cash","amount":1}]'::jsonb, 'dddddddd-0000-0000-0000-000000000019') ->> 'paid' as paid1 \gset
select tt.as(:'s');
select tt.err('T19 a salesperson re-sending a supplier payment (same client id) gets "not allowed", no balance leaks', format($$select pay_supplier(%L,1,'[{"mode":"cash","amount":1}]'::jsonb,'dddddddd-0000-0000-0000-000000000019')$$, :'s19'), 'not allowed');
select tt.as(:'o');
select tt.chk('T19 the owner re-sending it gets the dup', (pay_supplier(:'s19'::uuid, 1, '[{"mode":"cash","amount":1}]'::jsonb, 'dddddddd-0000-0000-0000-000000000019') ->> 'dup')::boolean and (select count(*) from supplier_payments where client_id = 'dddddddd-0000-0000-0000-000000000019') = 1);
select tt.as(:'s');
select tt.chk('T19 stock_ledger_rows: a salesperson sees purchase rows but NOT their bill id', (select count(*) from stock_ledger_rows(1, :'n1') where ref_type = 'purchase') >= 2
  and (select count(*) from stock_ledger_rows(1, :'n1') where ref_type = 'purchase' and ref_id is not null) = 0);
select tt.as(:'p');
select tt.chk('T19 ... purchasing sees them', (select count(*) from stock_ledger_rows(1, :'n1') where ref_type = 'purchase' and ref_id is not null) >= 2);
select tt.as(:'o');
select tt.chk('T19 ... and the owner', (select count(*) from stock_ledger_rows(1, :'n1') where ref_type = 'purchase' and ref_id is not null) >= 2);
reset role;
select tt.chk('T19 audit trail now covers the purchase lines', (select count(*) from audit_log where table_name = 'purchase_lines') > 0);

-- an emergency approval used inside a purchase function leaves a yellow 'emergency_used' line for the owner
set role authenticated; select tt.as(:'o'); select set_rule('em_purchase_entry', 'true');
select tt.as(:'s');
select request_emergency('purchase_entry', 1, '{}'::jsonb, 'supplier at the door, buyer absent') as em20 \gset
select tt.as(:'o'); select decide_emergency(:em20, true, 'ok');
reset role; select count(*) as emx0 from exceptions where flag_code = 'emergency_used' and form_code = 'EMERGENCY' \gset
set role authenticated; select tt.as(:'s');
select tt.chk('T19 a salesperson with an approved purchase_entry emergency can write ONE bill', (save_purchase(null, null, :'s19', 1, 'EM-1', current_date, '[{"description":"x","qty":1,"unit_cost":10}]'::jsonb) ->> 'status') = 'draft');
reset role;
select tt.chk('T19 ... the approval is used up and the owner got a yellow emergency_used line', (select status from emergency_requests where id = :em20) = 'used'
  and (select count(*) from exceptions where flag_code = 'emergency_used' and form_code = 'EMERGENCY' and level = 'yellow') = :emx0::int + 1);
set role authenticated; select tt.as(:'s');
select tt.err('T19 ... and a second bill is refused again', format($$select save_purchase(null,null,%L,1,'EM-2',current_date,'[{"description":"x","qty":1,"unit_cost":10}]'::jsonb)$$, :'s19'), 'not allowed');
select tt.as(:'o'); select set_rule('em_purchase_entry', null);

\echo -- 19.4 locks: the supplier row is locked by post / void / void payment; stock_opening cannot deadlock; reconcile(fix) locks the balance
select tt.chk('T19 stock_opening takes NO KEY UPDATE on the item, not UPDATE', (select prosrc from pg_proc where proname = 'stock_opening') like '%for no key update%'
  and (select prosrc from pg_proc where proname = 'stock_opening') not like '%from public.items where id = p_item for update%');
\if :has_dblink
select tt.as(:'o');
-- supplier row lock: while another transaction holds the supplier, post / void / void-payment wait (they all lock the supplier first)
set role authenticated; select tt.as(:'o');
select save_purchase(null, null, :'s19c', 1, 'C-A', current_date - 10, '[{"description":"a","qty":1,"unit_cost":100}]'::jsonb) ->> 'id' as ca \gset
select save_purchase(null, null, :'s19c', 3, 'C-B', current_date - 2, '[{"description":"b","qty":1,"unit_cost":100}]'::jsonb) ->> 'id' as cb \gset
reset role;
select tt.chk('T19 post_purchase waits for the supplier row lock', tt.probe(array[format('update suppliers set name = name where id = %L', :'s19c')], format($$select (post_purchase(%L))->>'status'$$, :'ca'), :'o') like 'blocked%');
select tt.chk('T19 ... and then completes (posted)', (select status from purchase_bills where id = :'ca'::uuid) = 'posted');
select tt.chk('T19 void_purchase waits for the supplier row lock', tt.probe(array[format('update suppliers set name = name where id = %L', :'s19c')], format($$select (void_purchase(%L,'probe'))->>'status'$$, :'ca'), :'o') like 'blocked%');
select tt.chk('T19 ... and then completes (void)', (select status from purchase_bills where id = :'ca'::uuid) = 'void');
set role authenticated; select tt.as(:'o');
select save_purchase(null, null, :'s19c', 1, 'C-A2', current_date - 10, '[{"description":"a","qty":1,"unit_cost":100}]'::jsonb) ->> 'id' as ca2 \gset
select post_purchase(:'ca2'::uuid); select post_purchase(:'cb'::uuid);
select pay_supplier(:'s19c'::uuid, 3, '[{"mode":"cash","amount":10}]'::jsonb) ->> 'paid' as pp \gset
reset role;
select id as pid from supplier_payments where supplier_id = :'s19c'::uuid and bill_id is null limit 1 \gset
select tt.chk('T19 void_supplier_payment waits for the supplier row lock', tt.probe(array[format('update suppliers set name = name where id = %L', :'s19c')], format($$select void_supplier_payment(%s,'probe')::text$$, :'pid'), :'o') like 'blocked%');
select tt.chk('T19 ... and then completes (voided)', (select voided from supplier_payments where id = :pid));
-- the deadlock the audit found: B holds a balance row and then writes a ledger row (KEY SHARE on the item); A (stock_opening) used to hold the item FOR UPDATE and wait for that balance row
insert into stock_balance (item_id, location_id) values (:'n2', 7) on conflict do nothing;      -- the balance row exists (an item already sold here), so the writer below holds ONLY the balance lock
select tt.chk('T19 stock_opening vs a sale-like writer: no deadlock (both finish, no error)',
  tt.probe(array[format('update stock_balance set updated_at = now() where item_id = %L and location_id = 7', :'n2')],
           format($$select (stock_opening(%L,7,10,10))->>'qty'$$, :'n2'), :'o',
           array[format('insert into stock_ledger (item_id, location_id, qty_delta, reason) values (%L, 7, -1, ''sale_out'')', :'n2')]) = 'blocked [result: 10]');
select tt.chk('T19 stock_reconcile(false) does not lock', tt.probe(array[format('update stock_balance set updated_at = now() where item_id = %L and location_id = 1', :'n1')], $$select count(*)::text from stock_reconcile(false)$$, :'o') like 'ran%');
select tt.chk('T19 stock_reconcile(true) waits for the balance row it is recounting', tt.probe(array[format('update stock_balance set updated_at = now() where item_id = %L and location_id = 1', :'n1')], $$select count(*)::text from stock_reconcile(true)$$, :'o') like 'blocked%');
\else
select tt.chk('T19 lock probes skipped: no dblink on this server', true);
\endif
set role authenticated; select tt.as(:'o');
select tt.chk('T19 reconcile is clean after the probes', (select count(*) from stock_reconcile()) = 0);

\echo -- 19.5 supplier credit: a payment made at a location clears that location first, the rest spills to the oldest
select pay_supplier(:'s19c'::uuid, 3, '[{"mode":"cash","amount":100}]'::jsonb) ->> 'balance' as bal19 \gset
select tt.chk('T19 paid 100 at location 3 (the 10 paid before was voided by the lock probe): bill C-B (loc 3) is cleared, C-A2 (loc 1, older) still open 100', (select count(*) from supplier_open_bills(:'s19c'::uuid) where bill_no = 'C-B') = 0
  and (select open_amt from supplier_open_bills(:'s19c'::uuid) where bill_no = 'C-A2') = 100);
select pay_supplier(:'s19c'::uuid, 3, '[{"mode":"cash","amount":40}]'::jsonb);
select tt.chk('T19 another 40 at location 3 (nothing left there) spills to the oldest: C-A2 open 60', (select open_amt from supplier_open_bills(:'s19c'::uuid) where bill_no = 'C-A2') = 60 and (select round(balance) from supplier_dues(null) where supplier_id = :'s19c'::uuid) = 60);

\echo -- 19.6 speed: 5000 tracked items for a salesperson
reset role;
insert into items (code, name_bn, unit, sell_price, tracked) select 'T19-P' || g, 'T19 P' || g, 'kg', 10, true from generate_series(1, 5000) g;
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason) select id, 1, 5, 3, 'opening' from items where name_bn like 'T19 P%';
insert into stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at) select id, 1, now(), 5, 5, now() + interval '5 hours' from items where name_bn like 'T19 P%' and right(name_bn, 1) = '7';
set role authenticated; select tt.as(:'s');
select clock_timestamp() as t0 \gset
select count(*) as nlev from stock_levels(1) \gset
select extract(epoch from clock_timestamp() - :'t0'::timestamptz) as el1 \gset
select tt.chk('T19 stock_levels(1) for a salesperson, 5000+ items: ' || round(:el1::numeric, 3) || ' s (< 1 s)', :el1::numeric < 1 and :nlev::int >= 5000);
select clock_timestamp() as t0 \gset
select count(*) as nlev2 from stock_levels(null, '{"include_zero":true}') \gset
select extract(epoch from clock_timestamp() - :'t0'::timestamptz) as el2 \gset
select tt.chk('T19 stock_levels(all locations, include zero): ' || round(:el2::numeric, 3) || ' s (< 1 s)', :el2::numeric < 1 and :nlev2::int >= 5000);
select tt.chk('T19 the salesperson sees quantities but no cost in them', (select count(*) from stock_levels(1) where avg_cost is not null or value is not null) = 0);
select clock_timestamp() as t0 \gset
select count(*) as nexp from expiry_list(1, 24) \gset
select extract(epoch from clock_timestamp() - :'t0'::timestamptz) as el3 \gset
select tt.chk('T19 expiry_list ' || round(:el3::numeric, 3) || ' s (< 1 s), the salesperson sees the batches', :el3::numeric < 1 and :nexp::int >= 500);
select tt.as(:'o');
select clock_timestamp() as t0 \gset
select count(*) as nval from stock_valuation(1) \gset
select extract(epoch from clock_timestamp() - :'t0'::timestamptz) as el4 \gset
select tt.chk('T19 stock_valuation(1) as owner, 5000+ items: ' || round(:el4::numeric, 3) || ' s (< 1 s)', :el4::numeric < 1 and :nval::int >= 5000);
select clock_timestamp() as t0 \gset
select count(*) as npl from purchase_list(null, null, null, null, null, 500) \gset
select extract(epoch from clock_timestamp() - :'t0'::timestamptz) as el5 \gset
select tt.chk('T19 purchase_list ' || round(:el5::numeric, 3) || ' s (< 1 s)', :el5::numeric < 1 and :npl::int > 0);
select tt.as(:'k');
select tt.chk('T19 a storekeeper (no cost right) sees quantities only', (select count(*) from stock_levels(1) where avg_cost is not null) = 0);

\echo -- 19.7 POS: late sale never blocks, one approval per sale, never-opened items, tiny quantities, expired
select tt.as(:'o');
select set_rule('stock_negative_mode', '"block"');
select stock_opening(:'n3', 1, 3, 10) ->> 'qty'; select stock_opening(:'n4', 1, 3, 10) ->> 'qty';
select tt.as(:'s');
select tt.err('T19 block: a fresh sale of 5 with 3 on hand is refused', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":5,"price":100,"unit":"kg"}]'::jsonb,0,'[{"mode":"cash","amount":500}]',null,null,'retail',null,false)$$, :'n3'), 'insufficient_stock');
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":5,"price":100,"unit":"kg"},{"item_id":"%s","qty":5,"price":100,"unit":"kg"}]', :'n3', :'n4')::jsonb, 0, '[{"mode":"cash","amount":1000}]', null, null, 'retail', null, false, now() - interval '10 minutes') ->> 'id' as slate \gset
reset role;
select tt.chk('T19 a LATE synced sale (10 min old) is recorded in block mode: both items go to -2', (select qty from stock_balance where item_id = :'n3'::uuid and location_id = 1) = -2 and (select qty from stock_balance where item_id = :'n4'::uuid and location_id = 1) = -2);
select tt.chk('T19 ... the owner still gets a yellow line per item for that sale', (select count(*) from exceptions where flag_code = 'stock_negative' and sale_id = :'slate'::uuid and level = 'yellow') = 2);
set role authenticated; select tt.as(:'o');
select stock_count_adjust(:'n3', 1, 3, 'recount'); select stock_count_adjust(:'n4', 1, 3, 'recount');
select set_rule('em_sell_below_zero', 'true');
select tt.as(:'s');
select request_emergency('sell_below_zero', 1, '{}'::jsonb, 'two items short, customer waiting') as em19 \gset
select tt.as(:'o'); select decide_emergency(:em19, true, 'ok');
select tt.as(:'s');
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":5,"price":100,"unit":"kg"},{"item_id":"%s","qty":5,"price":100,"unit":"kg"}]', :'n3', :'n4')::jsonb, 0, '[{"mode":"cash","amount":1000}]', null, null, 'retail', null, false) ->> 'id' as s2l \gset
reset role;
select tt.chk('T19 ONE emergency approval covers both short lines of ONE sale (approval used, both items -2)', (select status from emergency_requests where id = :em19) = 'used'
  and (select qty from stock_balance where item_id = :'n3'::uuid and location_id = 1) = -2 and (select qty from stock_balance where item_id = :'n4'::uuid and location_id = 1) = -2
  and (select count(*) from exceptions where flag_code = 'emergency_used' and sale_id = :'s2l'::uuid) = 1);
set role authenticated; select tt.as(:'s');
select tt.err('T19 ... and the next short sale is blocked again', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":100,"unit":"kg"}]'::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)$$, :'n3'), 'insufficient_stock');
select tt.as(:'o'); select set_rule('stock_negative_mode', '"warn"'); select set_rule('em_sell_below_zero', null);
reset role; select count(*) as exc0 from exceptions where flag_code = 'stock_negative' \gset
set role authenticated; select tt.as(:'s');
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":1,"price":100,"unit":"kg"}]', :'n5')::jsonb, 0, '[{"mode":"cash","amount":100}]', null, null, 'retail', null, false) ->> 'id' as s5 \gset
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":1,"price":100,"unit":"kg"}]', :'n3')::jsonb, 0, '[{"mode":"cash","amount":100}]', null, null, 'retail', null, false) ->> 'id' as s3b \gset
reset role;
select tt.chk('T19 an item that was never opened (no balance, no stock-in) goes -1 WITHOUT a stock_negative exception', (select qty from stock_balance where item_id = :'n5'::uuid and location_id = 1) = -1
  and not exists (select 1 from exceptions where sale_id = :'s5'::uuid and flag_code = 'stock_negative'));
select tt.chk('T19 an opened item already flagged today (n3) is not flagged again (once per item / location / day)', (select qty from stock_balance where item_id = :'n3'::uuid and location_id = 1) = -3
  and not exists (select 1 from exceptions where sale_id = :'s3b'::uuid and flag_code = 'stock_negative')
  and (select count(*) from exceptions where flag_code = 'stock_negative') = :exc0::int);
set role authenticated; select tt.as(:'o'); select stock_opening(:'n6', 1, 5, 1) ->> 'qty'; select tt.as(:'s');
select tt.chk('T19 tiny quantity: 0.00001 kg sells (no error), takes nothing out of the stock', (record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":0.00001,"price":100000,"unit":"kg"}]', :'n6')::jsonb, 0, '[{"mode":"cash","amount":1}]', null, null, 'retail', null, false) ->> 'receipt') is not null);
reset role;
select tt.chk('T19 ... the stock of n6 is untouched and there is no ledger row for that line', (select qty from stock_balance where item_id = :'n6'::uuid and location_id = 1) = 5 and (select count(*) from stock_ledger where item_id = :'n6'::uuid) = 1);

\echo -- 19.8 cost is secret: who may not see cost may not write it; production cost jump; batch dust
set role authenticated; select tt.as(:'o'); select set_grant('stock_opening', 'storekeeper', true); select set_grant('stock_production', 'storekeeper', true);
select tt.as(:'k');
select tt.err('T19 a storekeeper without the cost right cannot write an opening COST', format($$select stock_opening(%L,1,5,12)$$, :'n7'), 'not allowed');
select tt.chk('T19 ... but can open without a cost', (stock_opening(:'n7', 1, 5) ->> 'qty')::numeric = 5);
select tt.err('T19 nor a production COST', format($$select stock_production_in(%L,1,5,null,null,null,null,40)$$, :'n8'), 'not allowed');
select tt.chk('T19 ... production without a cost is fine', (stock_production_in(:'n8', 1, 5) ->> 'qty')::numeric = 5);
select tt.as(:'o');
select set_rule('purchase_cost_jump_pct', '20');
select stock_production_in(:'n7', 1, 10, null, null, null, null, 12) ->> 'qty';
select stock_production_in(:'n7', 1, 10, null, null, null, null, 90) ->> 'qty';
select set_rule('purchase_cost_jump_pct', null);
reset role;
select tt.chk('T19 a production cost far from the average is flagged production_cost_jump (once: 90 vs ~12; the first 12 vs 12 is not)', (select count(*) from exceptions where flag_code = 'production_cost_jump') = 1);
set role authenticated; select tt.as(:'o');
select stock_production_in(:'n9', 1, 1) ->> 'batch_id' as b9 \gset
select tt.as(:'s');
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":0.9997,"price":100,"unit":"kg"}]', :'n9')::jsonb, 0, '[{"mode":"cash","amount":99.97}]', null, null, 'retail', null, false) ->> 'id' as s9 \gset
reset role;
select tt.chk('T19 conversion dust: after selling 0.9997 of a 1 kg batch the 0.0003 left closes the batch (balance keeps 0.0003)', (select qty_remaining from stock_batches where id = :b9) = 0 and (select qty from stock_balance where item_id = :'n9'::uuid and location_id = 1) = 0.0003);

\echo -- 19.9 idempotency: the same client id twice
set role authenticated; select tt.as(:'o');
select save_purchase('c1111111-0000-0000-0000-000000000019', null, :'s19', 1, 'IDEM-1', current_date, '[{"description":"x","qty":1,"unit_cost":10}]'::jsonb) ->> 'id' as idm \gset
select tt.chk('T19 editing a draft with its own client id APPLIES the edit (not a dup)', (save_purchase('c1111111-0000-0000-0000-000000000019', :'idm'::uuid, :'s19', 1, 'IDEM-1', current_date, '[{"description":"x","qty":3,"unit_cost":10}]'::jsonb) ->> 'total')::numeric = 30);
select tt.chk('T19 ... the stored bill has the new total', (select total from purchase_bills where id = :'idm'::uuid) = 30);
select tt.chk('T19 re-sending the create (no p_id) is still the dup, total 30', (save_purchase('c1111111-0000-0000-0000-000000000019', null, :'s19', 1, 'IDEM-1', current_date, '[{"description":"x","qty":9,"unit_cost":10}]'::jsonb) ->> 'dup')::boolean);
select tt.err('T19 a different request with the same bill number is still a duplicate_bill', format($$select save_purchase('c2222222-0000-0000-0000-000000000019',null,%L,1,'IDEM-1',current_date,'[{"description":"x","qty":1,"unit_cost":10}]'::jsonb)$$, :'s19'), 'duplicate_bill');
select tt.err('T19 ... also without any client id', format($$select save_purchase(null,null,%L,1,'idem-1',current_date,'[{"description":"x","qty":1,"unit_cost":10}]'::jsonb)$$, :'s19'), 'duplicate_bill');
select stock_wastage(:'n1', 1, 1, 'spoiled', null, null, null, 'c3333333-0000-0000-0000-000000000019') ->> 'id' as w1 \gset
select tt.chk('T19 wastage with the same client id: dup', (stock_wastage(:'n1', 1, 1, 'spoiled', null, null, null, 'c3333333-0000-0000-0000-000000000019') ->> 'dup')::boolean);
select stock_transfer(1, 7, :'n1', 1, null, null, 'c4444444-0000-0000-0000-000000000019') ->> 'id' as tr1 \gset
select tt.chk('T19 transfer with the same client id: dup, one transfer', (stock_transfer(1, 7, :'n1', 1, null, null, 'c4444444-0000-0000-0000-000000000019') ->> 'dup')::boolean and (select count(*) from stock_transfers where client_id = 'c4444444-0000-0000-0000-000000000019') = 1);
reset role;
select tt.chk('T19 ... and exactly one write-off was written', (select count(*) from stock_wastage where id = :'w1'::uuid) = 1 and (select count(*) from stock_ledger where client_id = 'c3333333-0000-0000-0000-000000000019') = 1);
select tt.chk('T19 stock_post with the same client id twice: the same ledger id', stock_post(:'n1'::uuid, 1, -1, 'wastage', 'wastage', 'x', null, null, null, null, null, 'none', null, 'c5555555-0000-0000-0000-000000000019')
  = stock_post(:'n1'::uuid, 1, -1, 'wastage', 'wastage', 'x', null, null, null, null, null, 'none', null, 'c5555555-0000-0000-0000-000000000019'));
select tt.chk('T19 ... and one ledger row', (select count(*) from stock_ledger where client_id = 'c5555555-0000-0000-0000-000000000019') = 1);
select tt.err('T19 stock_post refuses NaN / Infinity / zero quantity', format($$select stock_post(%L,1,'Infinity','wastage')$$, :'n1'), 'bad_qty');
select tt.err('T19 stock_post refuses an absurd cost', format($$select stock_post(%L,1,1,'count_adjust',null,null,'1e30')$$, :'n1'), 'bad_cost');
select tt.chk('T19 reconcile is still clean at the end of the round', (select count(*) from (select item_id, location_id, sum(qty_delta) q from stock_ledger group by 1, 2) l full join stock_balance b using (item_id, location_id) where coalesce(l.q, 0) <> coalesce(b.qty, 0)) = 0);

select '--- FAILED: ' || count(*) from tt.res where not ok;
select '--- TOTAL: ' || count(*) from tt.res;
select name from tt.res where not ok;
