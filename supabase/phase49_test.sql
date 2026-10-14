-- FRESH DB ONLY. Phase 49 tests (P1 slice 2: day book vs journal, duplicate suspects).
--   ORDER="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase18 phase19 phase20 phase21 phase22 phase23 phase24 phase25 phase26 phase27 phase28 phase40 phase41 phase42 phase43 phase44 phase45 phase46 phase47 phase48 phase49" bash tests/sql/build_fresh_db.sh a49db
--   psql -h /tmp -p 5544 -U postgres -d a49db -qAt -f supabase/phase49_test.sql | grep -E 'FAIL|RESULT'
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
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
grant execute on function tt.today() to authenticated, anon;
with i as (insert into items (name_bn, name_en, unit, base_unit, sell_price, tracked, item_type) values ('Sweet','Sweet','kg','kg',500,true,'finished_good') returning id) select id as ifg from i \gset

\echo == T0 closed doors
select tt.chk('T0 anon has no execute', not has_function_privilege('anon','public.daybook_vs_journal(date,date,int)','execute') and not has_function_privilege('anon','public.dup_suspects(date,date)','execute'));
select tt.as(:'k');
select tt.err('T0 storekeeper cannot read the day book vs journal report', $$select daybook_vs_journal(tt.today()-1, tt.today())$$, 'not allowed');
select tt.err('T0 storekeeper cannot read duplicate suspects', $$select dup_suspects(tt.today()-1, tt.today())$$, 'not allowed');
select tt.as(:'o');
select tt.err('T0 bad range', $$select daybook_vs_journal(tt.today(), tt.today()-1)$$, 'bad_range');
select tt.chk('T0 data needed while the accounting start date is empty', (daybook_vs_journal(tt.today()-1, tt.today())->>'data_needed')::boolean);

\echo == T1 day book vs journal
select acct_set_start(tt.today() - 1) is not null as st \gset
select set_rule('accounting_on','true') is null as on1 \gset
select record_sale2(gen_random_uuid(),1,'[{"amount":100}]',0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,true) ->> 'id' as s1 \gset
select cash_move_add(1,'owner_topup',5000,null,'cash',null,null,null,gen_random_uuid()) ->> 'id' as cm2 \gset
select cash_move_add(1,'bank_deposit',300,null,null,null,'slip',null,gen_random_uuid()) ->> 'id' as cm1 \gset
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('10-2',1,9101,tt.today(),'approved','{"lines":[{"head":"transport","amount":"80","receipt":"yes"}]}','[]',:'s','st'),
 ('10-2',1,9102,tt.today(),'submitted','{"lines":[{"head":"transport","amount":"120","receipt":"yes"}]}','[]',:'s','st');
select tt.as(:'o');
select acct_post_pending(false)->>'posted' as pn \gset
select tt.chk('T1 posted sale + 2 cash moves + approved voucher', :'pn'::int=4);
select daybook_vs_journal(tt.today()-1, tt.today()) as r1 \gset
select tt.chk('T1 only the submitted-not-approved voucher differs: day book -200, journal -80, diff -120 (cash)',
  jsonb_array_length(:'r1'::jsonb->'rows')=1 and :'r1'::jsonb->'rows'->0->>'kind'='expense' and :'r1'::jsonb->'rows'->0->>'mode'='cash'
  and (:'r1'::jsonb->'rows'->0->>'daybook')::numeric=-200 and (:'r1'::jsonb->'rows'->0->>'journal')::numeric=-80 and (:'r1'::jsonb->'rows'->0->>'diff')::numeric=-120);
select tt.chk('T1 total diff is -120 and 1 kind differs', (:'r1'::jsonb->'total'->>'diff')::numeric=-120 and (:'r1'::jsonb->'total'->>'kinds_differing')::int=1);
update entries set status='approved' where form_code='10-2' and serial=9102;
select tt.as(:'o');
select acct_post_pending(false)->>'posted' as pn2 \gset
select daybook_vs_journal(tt.today()-1, tt.today()) as r2 \gset
select tt.chk('T1 after approval and posting nothing differs', :'pn2'::int=1 and jsonb_array_length(:'r2'::jsonb->'rows')=0 and (:'r2'::jsonb->'total'->>'diff')::numeric=0);
select tt.as(:'s');
select tt.err('T1 a manager without accounts_manage is refused', $$select daybook_vs_journal(tt.today()-1, tt.today())$$, 'not allowed');

\echo == T2 duplicate suspects (read-only)
with x as (insert into payroll_runs (month, location_id, status) values (date_trunc('month', tt.today())::date, 1, 'approved') returning id) select id as pr from x \gset
with x as (insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values ('02-2',1,9201,tt.today(),'submitted','{"pay":[]}','[]',:'s','st') returning id) select id as e22 from x \gset
insert into stock_ledger (item_id, location_id, qty_delta, reason, ref_type, ref_id, made_at) values (:'ifg', 1, -5, 'issue_out', 'entry', 'F-9301', now()), (:'ifg', 1, -5, 'issue_out', 'issue', 'S-1', now());
insert into stock_ledger (item_id, location_id, qty_delta, reason, ref_type, ref_id, made_at) values (:'ifg', 1, 7, 'production_in', 'entry', 'F-9302', now());
insert into cash_moves (location_id, kind, mode, amount, move_date, status, created_by) values (1, 'hub_receipt', 'cash', 900, tt.today(), 'done', :'o');
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values ('10-1',1,9401,tt.today(),'submitted','{}','[]',:'s','st');
select tt.as(:'o');
select dup_suspects(tt.today()-1, tt.today()) as d \gset
select tt.chk('T2 payroll: the run and the 02-2 sheet of the same month are listed', jsonb_array_length(:'d'::jsonb->'payroll')=1 and (:'d'::jsonb->'payroll'->0->>'run_id')::bigint=:'pr' and (:'d'::jsonb->'payroll'->0->>'entry_id')=:'e22');
select tt.chk('T2 stock: form line and screen line of the same item/day/qty are listed', jsonb_array_length(:'d'::jsonb->'stock')=1 and (:'d'::jsonb->'stock'->0->>'qty_delta')::numeric=-5);
select tt.chk('T2 handover: hub receipt and 10-1 of the same day are listed', jsonb_array_length(:'d'::jsonb->'handover')=1 and (:'d'::jsonb->'handover'->0->>'amount')::numeric=900);
select tt.chk('T2 production + owner_money lists are empty (no matching run / capital)', jsonb_array_length(:'d'::jsonb->'production')=0 and jsonb_array_length(:'d'::jsonb->'owner_money')=0);
select shadow_link_add('payroll',1,'payroll_runs',:'pr','entries',:'e22') is not null as lk \gset
select dup_suspects(tt.today()-1, tt.today()) as d2 \gset
select tt.chk('T2 once the 02-2 sheet is a locked shadow it is no longer a suspect', jsonb_array_length(:'d2'::jsonb->'payroll')=0);
select tt.chk('T2 the report wrote nothing (journal untouched by it)', (select count(*) from journal_entries where source_type not in ('opening'))=5);

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
