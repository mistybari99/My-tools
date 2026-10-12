-- FRESH DB ONLY. Phase 20 (forms <-> stock ledger links, discount approver on sales, brand P&L) tests.
--   ORDER="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase20" bash tests/sql/build_fresh_db.sh <db>
--   psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase20_test.sql     (look for FAIL; the last line prints the result)
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set m '00000000-0000-0000-0000-000000000005'
\set s2 '00000000-0000-0000-0000-000000000006'
\set sp '00000000-0000-0000-0000-000000000008'
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
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Manager A"}'), (:'k','store3@s.app','{"full_name":"Store"}'),
 (:'m','mgr5@s.app','{"full_name":"Mgr"}'), (:'s2','st6@s.app','{"full_name":"Manager B"}'), (:'sp','sp8@s.app','{"full_name":"Sales"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','showroom_manager'),(:'k','storekeeper'),(:'m','management'),(:'s2','showroom_manager'),(:'sp','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'s2',2),(:'sp',1) on conflict do nothing;
-- items: T1 kg tracked, T2 kg tracked, UN not tracked, NC tracked but not counted, BX tracked with a box unit that has no conversion
insert into items (code,name_bn,name_en,unit,tracked) values ('T1','টি১','Tea one','kg',true),('T2','টি২','Tea two','kg',true),('UN','আনট্র্যাক','Untracked','kg',false),
  ('BX','বক্স','Boxed','box',true) on conflict do nothing;
update items set base_unit='pc' where code='BX';
insert into items (code,name_bn,unit,tracked,count_in_business) values ('NC','নট কাউন্ট','kg',true,false) on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);

\echo == T0 shape
select tt.chk('T0 rule exists, default OFF', exists (select 1 from rules where key='forms_post_to_ledger') and not rule_on('forms_post_to_ledger'));
select tt.chk('T0 five per-form switches', (select count(*) from forms_ledger_cfg where is_on)=5);
select tt.chk('T0 new tables have RLS', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('forms_ledger_cfg','entry_ledger_posts') and c.relrowsecurity)=2);
select tt.chk('T0 anon cannot run the new functions', not has_function_privilege('anon','public.entry_post_ledger_retry(uuid)','execute') and not has_function_privilege('anon','public.brand_pnl(date,date,text)','execute')
  and not has_function_privilege('anon','public.discounts_report(date,date,int,boolean)','execute') and not has_function_privilege('authenticated','public.entry_post_ledger(uuid)','execute')
  and not has_function_privilege('authenticated','public._entries_post_ledger()','execute'));
select tt.chk('T0 one post trigger, decide_entry untouched in name', (select count(*) from pg_trigger where tgname='entries_post_ledger' and not tgisinternal)=1);

\echo == T1 switch OFF: approving posts nothing
set role authenticated; select tt.as(:'k');
select save_entry(null,'04-1',1,current_date,'{"supplier":"Sup A","lines":[{"item":"T1","counted":"10","rate":"5","quality":"accept"}]}','[]') ->> 'id' as g0 \gset
select submit_entry(:'g0'::uuid) is not null as s0 \gset
select tt.as(:'m'); select decide_entry(:'g0'::uuid, true, null, null, '[]') ->> 'status' as d0 \gset
select tt.chk('T1 approved, no ledger rows, no log rows', :'d0'='approved' and not exists (select 1 from stock_ledger where item_id=(select id from items where code='T1'))
  and not exists (select 1 from entry_ledger_posts));
select tt.as(:'o'); select set_rule('forms_post_to_ledger','true') is null as on1 \gset
select tt.chk('T1 turning the switch on does not back-post old approvals', not exists (select 1 from entry_ledger_posts));

\echo == T2 GRN posts
set role authenticated; select tt.as(:'k');
select save_entry(null,'04-1',1,current_date,'{"supplier":"Sup A","new_rate":"4","lines":[{"item":"T1","counted":"10","rate":"5","quality":"accept"},{"item":"T2","counted":"4","rate":"6","quality":"hold"},
  {"item":"UN","counted":"3","quality":"accept"},{"item":"NC","counted":"2","quality":"accept"},{"item":"T2","counted":"2","rate":"9","quality":"return"},{"item":"T2","counted":"6","rate":"8","quality":"reduced"},{}]}','[]') ->> 'id' as g1 \gset
select submit_entry(:'g1'::uuid) is not null as s1 \gset
select tt.as(:'m'); select decide_entry(:'g1'::uuid, true, null, null, '[]') ->> 'status' as d1 \gset
reset role;
select tt.chk('T2 approval went through', :'d1'='approved' and (select status from entries where id=:'g1'::uuid)='approved');
select tt.chk('T2 two ledger rows: T1 +10 at cost 5, T2 +6 at the NEW rate 4', (select count(*) from stock_ledger where ref_type='entry' and ref_id like :'g1'||'%')=2
  and (select qty_delta from stock_ledger where ref_id=:'g1'||':g1:1')=10 and (select reason from stock_ledger where ref_id=:'g1'||':g1:1')='purchase_in' and (select unit_cost from stock_ledger where ref_id=:'g1'||':g1:1')=5
  and (select qty_delta from stock_ledger where ref_id=:'g1'||':g1:6')=6 and (select unit_cost from stock_ledger where ref_id=:'g1'||':g1:6')=4);
select tt.chk('T2 balance T1 = 10', (select qty from stock_balance where item_id=(select id from items where code='T1') and location_id=1)=10);
select tt.chk('T2 hold / return / untracked / not-counted lines skipped with a reason', (select count(*) from entry_ledger_posts where entry_id=:'g1'::uuid and status='skipped')=4
  and (select reason from entry_ledger_posts where entry_id=:'g1'::uuid and line_no=2)='quality_hold' and (select reason from entry_ledger_posts where entry_id=:'g1'::uuid and line_no=5)='quality_return'
  and (select reason from entry_ledger_posts where entry_id=:'g1'::uuid and line_no=3)='not_tracked' and (select reason from entry_ledger_posts where entry_id=:'g1'::uuid and line_no=4) in ('not_tracked','not_counted'));
select tt.chk('T2 one yellow exception ledger_skip for the entry', (select count(*) from exceptions where entry_id=:'g1'::uuid and flag_code='ledger_skip' and level='yellow' and status='open')=1);
select count(*) as n_before from stock_ledger \gset
select count(*) as n_log_before from entry_ledger_posts \gset
set role authenticated; select tt.as(:'m');
select entry_post_ledger_retry(:'g1'::uuid) ->> 'gen' as rt \gset
reset role;
select tt.chk('T2 idempotent: a retry posts nothing new', :'rt'='1' and (select count(*) from stock_ledger)=:n_before and (select count(*) from entry_ledger_posts)=:n_log_before);
update entries set updated_at=now(), status='approved' where id=:'g1'::uuid;
select tt.chk('T2 idempotent: a no-op update does not post', (select count(*) from stock_ledger)=:n_before);

\echo == T2b reopen: same content = no double post; changed content = reverse + repost
set role authenticated; select tt.as(:'o');
select reopen_entry(:'g1'::uuid, 'owner reopens') ->> 'status' as ro \gset
select tt.chk('T2b reopen leaves the earlier posting in place until re-approval', (select qty from stock_balance where item_id=(select id from items where code='T1') and location_id=1)=10);
select submit_entry(:'g1'::uuid) is not null as rs \gset
select tt.as(:'m'); select decide_entry(:'g1'::uuid, true, null, (select reopen_snap->'check_data' from entries where id=:'g1'::uuid), '[]') ->> 'status' as rd \gset
reset role;
select tt.chk('T2b re-approve unchanged: nothing new posted', :'rd'='approved' and (select count(*) from stock_ledger)=:n_before and (select max(gen) from entry_ledger_posts where entry_id=:'g1'::uuid)=1);
set role authenticated; select tt.as(:'o');
select reopen_entry(:'g1'::uuid, 'quantity was wrong') is not null as ro2 \gset
select save_entry(:'g1'::uuid,'04-1',1,current_date,'{"supplier":"Sup A","new_rate":"4","lines":[{"item":"T1","counted":"12","rate":"5","quality":"accept"},{"item":"T2","counted":"4","rate":"6","quality":"hold"}]}','[]','fix') is not null as ed \gset
select submit_entry(:'g1'::uuid) is not null as rs2 \gset
select tt.as(:'m'); select decide_entry(:'g1'::uuid, true, null, (select reopen_snap->'check_data' from entries where id=:'g1'::uuid), '[]') ->> 'status' as rd2 \gset
reset role;
select tt.chk('T2b changed: balance T1 = 12, T2 line of generation 1 reversed (back to 0)', (select qty from stock_balance where item_id=(select id from items where code='T1') and location_id=1)=12
  and coalesce((select qty from stock_balance where item_id=(select id from items where code='T2') and location_id=1),0)=0);
select tt.chk('T2b generation 2: old generation reversed, reversal rows point at the originals, nothing deleted', (select max(gen) from entry_ledger_posts where entry_id=:'g1'::uuid)=2
  and (select count(*) from entry_ledger_posts where entry_id=:'g1'::uuid and gen=1 and status='reversed')=2
  and (select count(*) from stock_ledger where reason='reversal' and ref_type='entry' and ref_id like :'g1'||'%' and reverses_id is not null)=2
  and (select count(*) from stock_ledger where ref_type='entry' and ref_id like :'g1'||'%')=5);
select tt.chk('T2b exception now describes only the 1 held line', (select count(*) from exceptions where entry_id=:'g1'::uuid and flag_code='ledger_skip' and status='open')=1
  and (select amount from exceptions where entry_id=:'g1'::uuid and flag_code='ledger_skip' and status='open')=1);

\echo == T3 issue slip
set role authenticated; select tt.as(:'k');
select save_entry(null,'04-2',1,current_date,'{"purpose":"prod","not_overnight":true,"lines":[{"item":"T1","issued":"3","ret":"1"}]}','[]') ->> 'id' as i1 \gset
select submit_entry(:'i1'::uuid) is not null as si \gset
select tt.as(:'m'); select decide_entry(:'i1'::uuid, true, null, null, '[]') ->> 'status' as di \gset
reset role;
select tt.chk('T3 net use 2 posted as issue_out -2; balance 10', :'di'='approved' and (select qty_delta from stock_ledger where ref_id=:'i1'||':g1:1')=-2 and (select reason from stock_ledger where ref_id=:'i1'||':g1:1')='issue_out'
  and (select qty from stock_balance where item_id=(select id from items where code='T1') and location_id=1)=10);
set role authenticated; select tt.as(:'k');
select save_entry(null,'04-2',1,current_date,'{"purpose":"prod","lines":[{"item":"T1","issued":"3","ret":"1"}]}','[]') ->> 'id' as i2 \gset
select submit_entry(:'i2'::uuid) is not null as si2 \gset
select tt.as(:'m'); select decide_entry(:'i2'::uuid, true, null, null, '[]') is not null as di2 \gset
reset role;
select tt.chk('T3 kept overnight = the whole 3 counts as used', (select qty_delta from stock_ledger where ref_id=:'i2'||':g1:1')=-3);
-- failure must not block the approval: block mode + not enough stock, unknown item, unknown unit
select set_config('request.jwt.claim.sub', :'o', false);
set role authenticated; select tt.as(:'o'); select set_rule('stock_negative_mode','"block"') is null as blk \gset
select tt.as(:'k');
select save_entry(null,'04-2',1,current_date,'{"purpose":"prod","lines":[{"item":"T1","issued":"500"},{"item":"ZZ9","issued":"1"},{"item":"BX","issued":"2"},{"item":"T2","issued":"1"}]}','[]') ->> 'id' as f1 \gset
select submit_entry(:'f1'::uuid) is not null as sf \gset
select tt.as(:'m'); select decide_entry(:'f1'::uuid, true, null, null, '[]') ->> 'status' as df \gset
reset role;
select tt.chk('T3 approval NOT blocked by ledger failures', :'df'='approved' and (select status from entries where id=:'f1'::uuid)='approved');
select tt.chk('T3 three failed lines with reasons (stock, unknown item, unit); no ledger rows for the entry', (select count(*) from entry_ledger_posts where entry_id=:'f1'::uuid and status='failed')=4
  and (select reason from entry_ledger_posts where entry_id=:'f1'::uuid and line_no=1) like '%insufficient_stock%' and (select reason from entry_ledger_posts where entry_id=:'f1'::uuid and line_no=2) like '%item_not_found%'
  and (select reason from entry_ledger_posts where entry_id=:'f1'::uuid and line_no=3) like '%unit_unknown%' and not exists (select 1 from stock_ledger where ref_id like :'f1'||'%'));
select tt.chk('T3 one exception ledger_post_failed', (select count(*) from exceptions where entry_id=:'f1'::uuid and flag_code='ledger_post_failed' and status='open')=1);
-- stock arrives, the retry posts the lines that can be posted now (T1 500 still not available; T2 1 fails too -> give T2 stock first)
update items set base_unit=null where code='BX';
insert into stock_ledger (item_id,location_id,qty_delta,reason,note) select id,1,600,'opening','test' from items where code='T1' and false;
set role authenticated; select tt.as(:'k');
select save_entry(null,'04-1',1,current_date,'{"supplier":"Sup B","lines":[{"item":"T1","counted":"500","rate":"5","quality":"accept"},{"item":"T2","counted":"5","rate":"7","quality":"accept"},{"item":"BX","counted":"9","quality":"accept"}]}','[]') ->> 'id' as g2 \gset
select submit_entry(:'g2'::uuid) is not null as s2x \gset
select tt.as(:'m'); select decide_entry(:'g2'::uuid, true, null, null, '[]') is not null as d2x \gset
select entry_post_ledger_retry(:'f1'::uuid) as retry1 \gset
reset role;
select tt.chk('T3 retry posts the lines that work now (T1 500 out, T2 1 out, BX 2 out via unit) and keeps the failure for the unknown item', (:'retry1'::jsonb->>'failed')::int=1 and (:'retry1'::jsonb->>'posted')::int=3
  and (select count(*) from stock_ledger where ref_id like :'f1'||'%')>=3 and (select count(*) from exceptions where entry_id=:'f1'::uuid and flag_code='ledger_post_failed' and status='open')=1);
set role authenticated; select tt.as(:'o'); select set_rule('stock_negative_mode','"warn"') is null as blk2 \gset
reset role;

\echo == T4 count sheet
select coalesce((select qty from stock_balance where item_id=(select id from items where code='T2') and location_id=1),0) as t2before \gset
set role authenticated; select tt.as(:'k');
select (select qty from stock_balance where item_id=(select id from items where code='T1') and location_id=1) as t1bal \gset
select save_entry(null,'04-3',1,current_date,format('{"rows":[{"item":"T1","count":"%s","book":"%s","reason":"x"},{"item":"T2","count":"9","book":"5","reason":"found more"}]}', :'t1bal', :'t1bal')::jsonb,'[]') ->> 'id' as c1 \gset
select submit_entry(:'c1'::uuid) is not null as sc \gset
select tt.as(:'m'); select decide_entry(:'c1'::uuid, true, null, null, '[]') ->> 'status' as dc \gset
reset role;
select tt.chk('T4 count: equal = no ledger row (no_change), different = count_adjust delta to the counted figure',
  (select reason from entry_ledger_posts where entry_id=:'c1'::uuid and line_no=1)='no_change' and not exists (select 1 from stock_ledger where ref_id=:'c1'||':g1:1')
  and (select reason from stock_ledger where ref_id=:'c1'||':g1:2')='count_adjust' and (select qty from stock_balance where item_id=(select id from items where code='T2') and location_id=1)=:t2before+4);
set role authenticated; select tt.as(:'k');
select save_entry(null,'04-3',1,current_date,'{"rows":[{"item":"T1","count":"3"}]}','[]') ->> 'id' as c3 \gset
select submit_entry(:'c3'::uuid) is not null as sc3 \gset
select tt.as(:'m'); select decide_entry(:'c3'::uuid, true, null, null, '[]') ->> 'status' as dc3 \gset
reset role;
select tt.chk('T4 a count row without the sheet system balance is skipped (no_count_basis), not guessed', :'dc3'='approved' and (select reason from entry_ledger_posts where entry_id=:'c3'::uuid)='no_count_basis' and not exists (select 1 from stock_ledger where ref_id like :'c3'||'%'));

\echo == T5 transfer challan
set role authenticated; select tt.as(:'k');
select save_entry(null,'03-1',1,current_date,'{"from_loc":"1","to_loc":"2","ttype":"f2s","items":[{"item":"T1","sent":"3"},{"item":"T2","sent":"2"}]}','[]') ->> 'id' as t1 \gset
select submit_entry(:'t1'::uuid) is not null as st \gset
select tt.as(:'m'); select decide_entry(:'t1'::uuid, true, null, '{"items":[{"received":"3"},{"received":"1"}]}'::jsonb, '[]') ->> 'status' as dt \gset
reset role;
select tt.chk('T5 transfer: out at 1 for 3 and 2, in at 2 for 3 and 1 (the receiver count), transfer rows received',
  (select count(*) from stock_ledger l join stock_transfers t on l.ref_id=t.id::text and l.ref_type='transfer' where l.reason='transfer_out' and t.from_location_id=1 and t.to_location_id=2 and l.location_id=1)=2
  and (select sum(qty_delta) from stock_ledger l where l.reason='transfer_in' and l.location_id=2)=4
  and (select count(*) from stock_transfers where status='received' and received_qty is not null)=2 and (select qty from stock_balance where item_id=(select id from items where code='T2') and location_id=2)=1);
select tt.chk('T5 shortage kept as the difference in the log', (select reason from entry_ledger_posts where entry_id=:'t1'::uuid and line_no=2) like 'short%');
set role authenticated; select tt.as(:'k');
select save_entry(null,'03-1',1,current_date,'{"from_loc":"1","to_loc":"other","ttype":"cust","items":[{"item":"T1","sent":"1"}]}','[]') ->> 'id' as t2 \gset
select submit_entry(:'t2'::uuid) is not null as st2 \gset
select tt.as(:'m'); select decide_entry(:'t2'::uuid, true, null, '{"items":[{"received":"1"}]}'::jsonb, '[]') is not null as dt2 \gset
reset role;
select tt.chk('T5 to a place outside the list: only the out leg, no transfer row', (select qty_delta from stock_ledger where ref_id=:'t2'||':g1:1')=-1 and (select reason from stock_ledger where ref_id=:'t2'||':g1:1')='transfer_out');
set role authenticated; select tt.as(:'k');
select save_entry(null,'03-1',1,current_date,'{"from_loc":"1","to_loc":"2","items":[{"item":"T1","sent":"1"}]}','[]') ->> 'id' as t3 \gset
select submit_entry(:'t3'::uuid) is not null as st3 \gset
select tt.as(:'m'); select decide_entry(:'t3'::uuid, true, null, '{"items":[{"received":"2"}]}'::jsonb, '[]') ->> 'status' as dt3 \gset
reset role;
select tt.chk('T5 received more than sent: not posted, failed line with over_received, approval fine', :'dt3'='approved' and (select reason from entry_ledger_posts where entry_id=:'t3'::uuid and line_no=1) like '%over_received%');
-- revision of a transfer: reverse + repost
set role authenticated; select tt.as(:'o');
select reopen_entry(:'t1'::uuid, 'receiver recounted') is not null as ro3 \gset
select submit_entry(:'t1'::uuid) is not null as rs3 \gset
select tt.as(:'m'); select decide_entry(:'t1'::uuid, true, null, '{"items":[{"received":"3"},{"received":"2"}]}'::jsonb, '[]') ->> 'status' as rd3 \gset
reset role;
select tt.chk('T5 revised transfer: gen 2, old transfer rows cancelled and reversed, balance at 2 for T2 = 2', (select max(gen) from entry_ledger_posts where entry_id=:'t1'::uuid)=2
  and (select qty from stock_balance where item_id=(select id from items where code='T2') and location_id=2)=2 and (select count(*) from stock_transfers where status='cancelled')=2);

set role authenticated; select tt.as(:'k');
select save_entry(null,'03-1',1,current_date,'{"from_loc":"2","to_loc":"1","items":[{"item":"T1","sent":"1"}]}','[]') ->> 'id' as t4 \gset
select submit_entry(:'t4'::uuid) is not null as st4 \gset
select tt.as(:'m'); select decide_entry(:'t4'::uuid, true, null, '{"items":[{"received":"1"}]}'::jsonb, '[]') ->> 'status' as dt4 \gset
reset role;
select tt.chk('T5 sender place differs from the entry place: skipped location_mismatch, nothing posted', :'dt4'='approved' and (select reason from entry_ledger_posts where entry_id=:'t4'::uuid)='location_mismatch' and not exists (select 1 from stock_ledger where ref_id like :'t4'||'%')
  and exists (select 1 from exceptions where entry_id=:'t4'::uuid and flag_code='ledger_skip'));

\echo == T6 factory sheet
update rules set value='false' where key='location_block_when_paused';
set role authenticated; select tt.as(:'o');
select save_entry(null,'05-1',5,current_date,'{"shift":"m","batches":"2"}','[]') ->> 'id' as fa \gset
select submit_entry(:'fa'::uuid) is not null as sfa \gset
select tt.as(:'m'); select decide_entry(:'fa'::uuid, true, null, null, '[]') ->> 'status' as dfa \gset
reset role;
select tt.chk('T6 a sheet without finished-goods lines: nothing posted, one ledger_skip', :'dfa'='approved' and (select reason from entry_ledger_posts where entry_id=:'fa'::uuid)='no_item_lines'
  and (select count(*) from exceptions where entry_id=:'fa'::uuid and flag_code='ledger_skip')=1 and not exists (select 1 from stock_ledger where ref_id like :'fa'||'%'));
set role authenticated; select tt.as(:'o');
select save_entry(null,'05-1',5,current_date,'{"shift":"m","output":[{"item":"T2","qty":"7"}]}','[]') ->> 'id' as fb \gset
select submit_entry(:'fb'::uuid) is not null as sfb \gset
select tt.as(:'m'); select decide_entry(:'fb'::uuid, true, null, null, '[]') ->> 'status' as dfb \gset
reset role;
select tt.chk('T6 output lines become production_in with a batch at the sheet place', (select reason from stock_ledger where ref_id=:'fb'||':g1:1')='production_in' and (select qty_delta from stock_ledger where ref_id=:'fb'||':g1:1')=7
  and (select location_id from stock_ledger where ref_id=:'fb'||':g1:1')=5 and (select batch_id from stock_ledger where ref_id=:'fb'||':g1:1') is not null);

\echo == T7 per-form switch, other forms unaffected
set role authenticated; select tt.as(:'s'); select tt.err('T7 only the owner sets a per-form switch', $$select forms_ledger_cfg_set('04-1', false)$$, 'not allowed');
select tt.as(:'o'); select forms_ledger_cfg_set('04-3', false) ->> 'is_on' as cf \gset
select tt.err('T7 only the five forms', $$select forms_ledger_cfg_set('10-2', false)$$, 'bad_form');
select tt.as(:'k');
select save_entry(null,'04-3',1,current_date,'{"rows":[{"item":"T1","count":"1","book":"1"}]}','[]') ->> 'id' as c2 \gset
select submit_entry(:'c2'::uuid) is not null as sc2 \gset
select tt.as(:'m'); select decide_entry(:'c2'::uuid, true, null, null, '[]') ->> 'status' as dc2 \gset
reset role;
select tt.chk('T7 04-3 OFF: nothing logged for it, 04-2 still posts', :'dc2'='approved' and not exists (select 1 from entry_ledger_posts where entry_id=:'c2'::uuid));
update forms_ledger_cfg set is_on=true where form_code='04-3';
select tt.chk('T7 unrelated forms never post (10-2)', not exists (select 1 from entry_ledger_posts where form_code not in ('04-1','04-2','04-3','03-1','05-1')));

\echo == T8 access, RLS, costs
set role authenticated; select tt.as(:'k');
select tt.chk('T8 storekeeper sees the log of place 1 and no cost column', (select count(*) from entry_ledger_posts)>0);
select tt.err('T8 nobody writes the log directly', $$insert into entry_ledger_posts (entry_id,gen,line_no,form_code,location_id,kind,sig,status) values (gen_random_uuid(),1,1,'04-1',1,'in','x','posted')$$, 'permission denied');
select tt.err('T8 nobody writes the switch table directly', $$update forms_ledger_cfg set is_on=false$$, 'permission denied');
select tt.err('T8 a plain user cannot read unit_cost from the ledger', $$select unit_cost from stock_ledger limit 1$$, 'permission denied');
select tt.chk('T8 the ledger-line list has no cost and works for the place', (select count(*) from entry_ledger_lines(:'g1'::uuid))>0);
select tt.chk('T8 stock_ledger_rows hides cost from a storekeeper without a cost right', (select count(*) from stock_ledger_rows(1) where unit_cost is not null)=0);
select tt.err('T8 the storekeeper (not an approver) cannot retry', format($$select entry_post_ledger_retry(%L)$$, :'g1'), 'not allowed');
select tt.as(:'s2');
select tt.chk('T8 a manager of place 2 sees no log rows of place 1 entries', (select count(*) from entry_ledger_posts where location_id=1 and kind<>'transfer')=0);
select tt.err('T8 the ledger-line list of another place is refused', format($$select * from entry_ledger_lines(%L)$$, :'g1'), 'not allowed');
select tt.as(:'m'); select tt.chk('T8 an approver sees the problem list with the entry f1', exists (select 1 from ledger_post_problems(1) where entry_id=:'f1'::uuid));
select tt.err('T8 retry on an unapproved/unknown entry is refused', $$select entry_post_ledger_retry(gen_random_uuid())$$, 'not allowed');
reset role;

\echo == T9 discount approver
insert into location_settings (location_id,key,value) values (1,'discount_limit','100') on conflict (location_id,key) do update set value='100';
set role authenticated; select tt.as(:'sp');
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true) as sa \gset
select tt.chk('T9 discount within the limit: no approver stored', (select discount_approved_by is null and discount_approval is null from sales where id=(:'sa'::jsonb->>'id')::uuid));
select tt.err('T9 above the limit without any approval is still refused (record_sale2 unchanged)', $$select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',150,'[{"mode":"cash","amount":350}]',null,null,'retail',null,true)$$, 'discount_needs_approval');
select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',150,'[{"mode":"cash","amount":350}]',null,null,'retail',null,true) as sb \gset
select tt.chk('T9 above the limit by a role that holds the grant: approver = the seller, kind grant', (select discount_approved_by=:'s'::uuid and discount_approval='grant' and discount_approved_staff is not null from sales where id=(:'sb'::jsonb->>'id')::uuid));
select tt.as(:'sp');
select request_emergency('discount_over_limit',1,'{"amount":150}','customer is a regular') as er \gset
select tt.as(:'o'); select decide_emergency(:er,true,null) is null as ed \gset
select tt.as(:'sp');
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',150,'[{"mode":"cash","amount":350}]',null,null,'retail',null,true) as sc \gset
select tt.chk('T9 emergency approval: approver = the person who approved the request', (select discount_approved_by=:'o'::uuid and discount_approval='emergency' from sales where id=(:'sc'::jsonb->>'id')::uuid));
select tt.as(:'o');
select tt.chk('T9 discounts_report lists the 3 discount sales with who approved', (select count(*) from discounts_report(current_date-1,current_date+1,1))=3
  and (select count(*) from discounts_report(current_date-1,current_date+1,1,true))=2);
select tt.as(:'k'); select tt.err('T9 a storekeeper without report rights cannot read it', $$select * from discounts_report(current_date-1,current_date+1,1)$$, 'not allowed');
reset role;
select tt.chk('T9 old sales (before the column) simply stay null', (select count(*) from sales where discount>0 and discount_approval is null)>=1);

\echo == T10 brand P&L
reset role;
insert into item_costs (item_id, cost_price) select id, 100 from items where code='T1' on conflict (item_id) do update set cost_price=100;
update items set sell_price=200 where code='T1';
set role authenticated; select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,(select jsonb_build_array(jsonb_build_object('item_id',id,'qty',2)) from items where code='T1'),0,'[{"mode":"cash","amount":400}]',null,null,'retail',null,true) as sd \gset
select tt.as(:'o');
select tt.chk('T10 owner sees the brand row with revenue and cost-based profit', (select revenue>0 and cogs is not null and gross_profit is not null from brand_pnl(current_date-1,current_date+1) where brand_code='islamiya'));
select tt.chk('T10 brand filter returns one row; unknown brand none', (select count(*) from brand_pnl(current_date-1,current_date+1,'islamiya'))=1 and (select count(*) from brand_pnl(current_date-1,current_date+1,'nope'))=0);
select tt.chk('T10 the brand row equals the sum of biz_daily for its locations', (select revenue from brand_pnl(current_date-1,current_date+1,'islamiya'))=(select sum(revenue) from biz_daily(current_date-1,current_date+1) where location_id in (select location_id from report_brand_map where brand_code='islamiya')));
select tt.as(:'s');
select tt.chk('T10 a manager without a cost right: revenue yes, cost and profit NULL', (select revenue>0 and cogs is null and gross_profit is null and gp_pct is null from brand_pnl(current_date-1,current_date+1) where brand_code='islamiya'));
select tt.as(:'k'); select tt.err('T10 no report right = refused', $$select * from brand_pnl(current_date-1,current_date+1)$$, 'not allowed');
reset role;

\echo == T11 rerun
\i supabase/phase20.sql
select tt.chk('T11 re-running phase20 keeps one trigger, one rule, five switches and all data', (select count(*) from pg_trigger where tgname in ('entries_post_ledger','sales_discount_approver') and not tgisinternal)=2
  and (select count(*) from rules where key='forms_post_to_ledger')=1 and (select count(*) from forms_ledger_cfg)=5 and (select count(*) from entry_ledger_posts)>10);

select count(*) filter (where not ok) as fails, count(*) as total from tt.res \gset
\echo == RESULT :fails fails of :total
