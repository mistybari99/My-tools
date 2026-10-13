-- FRESH DB ONLY. Phase 51 tests (P1 slice 4: stock + production + owner money).
--   ORDER="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase18 phase19 phase20 phase21 phase22 phase23 phase24 phase25 phase26 phase27 phase28 phase40 phase41 phase42 phase43 phase44 phase45 phase46 phase47 phase48 phase49 phase50 phase51" bash tests/sql/build_fresh_db.sh a51db
--   psql -h /tmp -p 5544 -U postgres -d a51db -qAt -f supabase/phase51_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
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
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'k','store3@s.app','{"full_name":"Store"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','showroom_manager'),(:'k','storekeeper') on conflict do nothing;
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'k','storekeeper') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1) on conflict do nothing;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
grant execute on function tt.today() to authenticated, anon;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('T1','T1','T1','kg','kg','raw_material',true,0), ('FG','FG','FG','kg','kg','finished_good',true,10);
select id as it1 from items where code='T1' \gset
select id as ifg from items where code='FG' \gset

\echo == T0 shape
select tt.chk('T0 guards are closed to browsers; owner_money_link is owner-callable', not has_function_privilege('authenticated','public._stock_ledger_path_guard51()','execute') and has_function_privilege('authenticated','public.owner_money_link(bigint,uuid,text)','execute') and not has_function_privilege('anon','public.owner_money_link(bigint,uuid,text)','execute'));
select tt.chk('T0 bos51 blocks are in the two form-posting functions', position('bos51' in pg_get_functiondef('public.entry_post_ledger(uuid)'::regprocedure))>0 and position('bos51' in pg_get_functiondef('public._elp_post_line(entries,int,text,jsonb)'::regprocedure))>0);
select tt.chk('T0 stock domains remember the legacy rule', (select count(*) from path_domains where legacy_rule='forms_post_to_ledger')=4);

\echo == T1 screen primary: the form is a reference and posts nothing
select tt.as(:'o');
select stock_opening(:'it1'::uuid, 1, 100, 10, null, 'seed') is not null as op \gset
select set_rule('forms_post_to_ledger','true') is null as ron \gset
select path_switch_set('stock_issue',0,true,true,'a') is not null as sw1 \gset
select save_entry(null,'04-2',1,tt.today(),'{"purpose":"prod","not_overnight":true,"lines":[{"item":"T1","issued":"3","ret":"0"}]}','[]') ->> 'id' as f1 \gset
update entries set status='submitted' where id=:'f1'::uuid;
update entries set status='approved' where id=:'f1'::uuid;
select tt.chk('T1 approved 04-2 with primary=a: its ledger line is skipped (covered_by_screen), stock unchanged', (select status from entry_ledger_posts where entry_id=:'f1'::uuid)='skipped'
  and (select reason from entry_ledger_posts where entry_id=:'f1'::uuid)='covered_by_screen' and (select coalesce(sum(qty_delta),0) from stock_ledger where item_id=:'it1' and ref_type='entry')=0);
select stock_issue(:'it1'::uuid, 1, 3, null, 'screen issue') is not null as si \gset
select tt.chk('T1 the screen issue posts normally', (select coalesce(sum(qty_delta),0) from stock_ledger where item_id=:'it1' and reason='issue_out' and ref_type='issue')=-3);

\echo == T2 form primary: the form posts, the screen is blocked
select path_switch_set('stock_issue',0,true,true,'b') is not null as sw2 \gset
select save_entry(null,'04-2',1,tt.today(),'{"purpose":"prod","not_overnight":true,"lines":[{"item":"T1","issued":"4","ret":"0"}]}','[]') ->> 'id' as f2 \gset
update entries set status='submitted' where id=:'f2'::uuid;
update entries set status='approved' where id=:'f2'::uuid;
select tt.chk('T2 approved 04-2 with primary=b posts -4 (ref_type entry)', (select status from entry_ledger_posts where entry_id=:'f2'::uuid)='posted' and (select coalesce(sum(qty_delta),0) from stock_ledger where item_id=:'it1' and ref_type='entry')=-4);
select tt.err('T2 the stock screen issue is refused (never both posting)', format($$select stock_issue('%s'::uuid, 1, 1, null, 'again')$$, :'it1'), 'path_locked');
select tt.chk('T2 other kinds of ledger rows are untouched by the guard (count/opening still work)', stock_opening(:'ifg'::uuid, 1, 5, 20, null, 'seed2') is not null);

\echo == T3 locked paths
select path_switch_set('stock_issue',0,true,false,'a') is not null as sw3 \gset
select tt.err('T3 form path locked: a new 04-2 is refused', format($$select save_entry(null,'04-2',1,%L,'{"purpose":"x","lines":[]}','[]')$$, tt.today()), 'path_locked');
select path_switch_set('stock_issue',0,false,true,'a') is not null as sw4 \gset
select tt.err('T3 screen path locked: stock_issue is refused', format($$select stock_issue('%s'::uuid, 1, 1, null, 'x')$$, :'it1'), 'path_locked');
select path_switch_set('stock_issue',0,true,true,'a') is not null as sw5 \gset
select tt.chk('T3 reopened: screen works again', stock_issue(:'it1'::uuid, 1, 1, null, 'ok again') is not null);

\echo == T4 production + count + transfer follow the same rule
select path_switch_set('production',0,true,true,'b') is not null as sw6 \gset
select tt.err('T4 production_in by screen refused while the sheet 05-1 is the record', format($$select stock_production_in('%s'::uuid, 1, 2, now(), null, 'x')$$, :'ifg'), 'path_locked');
select path_switch_set('production',0,true,true,'a') is not null as sw7 \gset
select tt.chk('T4 production_in by screen works when primary=a', stock_production_in(:'ifg'::uuid, 1, 2, now(), null, 'x') is not null);
select path_switch_set('stock_count',0,false,true,'a') is not null as sw8 \gset
select tt.err('T4 count by screen refused when its path is locked', format($$select stock_count_adjust('%s'::uuid, 1, 90, 'x')$$, :'it1'), 'path_locked');

\echo == T5 owner money
select partner_party_save(null,'Owner Party','company','01711000000',null,null,null,null,null,true,gen_random_uuid()) ->> 'id' as pa \gset
select partner_party_save(null,'Ivy','individual',null,null,null,null,null,null,true,gen_random_uuid()) ->> 'id' as pb \gset
select partner_venture_save(null,'ভেঞ্চার','Venture','custom',null,'partnership','2026-01-01',null,'draft',null,gen_random_uuid()) ->> 'id' as v1 \gset
select partner_agreement_save(null, :'v1'::bigint, 'Deed', '2026-01-01', null, '[]'::jsonb, null, gen_random_uuid()) ->> 'id' as ag \gset
select partner_agreement_party_set(:'ag'::bigint, :'pa'::bigint, 'owner', null, null) is not null as p1 \gset
select partner_agreement_party_set(:'ag'::bigint, :'pb'::bigint, 'investor', null, null) is not null as p2 \gset
select partner_rule_save(:'ag'::bigint, null, 'Base', 'base', '{"base":"net_profit_before_fees"}'::jsonb) is not null as r1 \gset
select partner_rule_save(:'ag'::bigint, null, 'Split', 'split', '{"shares":[{"role":"owner","percent":50},{"role":"investor","percent":50}]}'::jsonb) is not null as r2 \gset
select partner_agreement_activate(:'ag'::bigint) is not null as act \gset
select partner_capital_add(:'ag'::bigint, :'pb'::bigint, 'contribution', 5000, tt.today(), 'cash', 'top up', 'R1', gen_random_uuid()) ->> 'id' as cap1 \gset
select cash_move_add(1,'owner_topup',5000,null,'cash',null,null,null,gen_random_uuid()) ->> 'id' as cm1 \gset
select cash_move_add(1,'owner_topup',700,null,'cash',null,null,null,gen_random_uuid()) ->> 'id' as cm2 \gset
select tt.err('T5 amounts must match', format($$select owner_money_link(%s,'%s')$$, :'cap1', :'cm2'), 'amount_mismatch');
select cash_move_add(1,'owner_draw',5000,null,'cash',null,null,null,gen_random_uuid()) ->> 'id' as cm3 \gset
select tt.err('T5 a draw cannot pair with a contribution', format($$select owner_money_link(%s,'%s')$$, :'cap1', :'cm3'), 'kind_mismatch');
select tt.as(:'s');
select tt.err('T5 only the owner links', format($$select owner_money_link(%s,'%s')$$, :'cap1', :'cm1'), 'not allowed');
select tt.as(:'o');
select owner_money_link(:'cap1'::bigint, :'cm1'::uuid) ->> 'primary' as pr \gset
select tt.chk('T5 default primary=a: partner capital is the record, the cash move is the shadow', :'pr'='partner_capital' and is_shadow('cash_moves', :'cm1') and not is_shadow('partner_capital', :'cap1'));
select tt.chk('T5 linking again is idempotent', (owner_money_link(:'cap1'::bigint, :'cm1'::uuid) ->> 'link')::bigint = (select id from shadow_links where primary_id=:'cap1'));
select tt.chk('T5 nothing is double counted today: the day book still shows the 2 cash moves once each, partner capital is not in the day book',
  (select count(*) from _daybook_lines23(array[1], tt.today(), tt.today()) where typ='owner_topup')=2);
select path_switch_set('owner_money',0,false,true,'a') is not null as sw9 \gset
select tt.err('T5 partner capital path locked: a new contribution is refused', format($$select partner_capital_add(%s,%s,'contribution',100,%L,'cash','x','R2',gen_random_uuid())$$, :'ag', :'pb', tt.today()), 'path_locked');
select path_switch_set('owner_money',0,true,false,'a') is not null as sw10 \gset
select tt.err('T5 cash move path locked: a new owner top-up is refused', $$select cash_move_add(1,'owner_topup',100,null,'cash',null,null,null,gen_random_uuid())$$, 'path_locked');
select tt.chk('T5 other cash move kinds are unaffected', cash_move_add(1,'bank_deposit',100,null,null,null,'slip',null,gen_random_uuid()) is not null);

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
