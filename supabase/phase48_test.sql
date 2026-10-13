-- FRESH DB ONLY. Phase 48 tests (P1 slice 1: path switches + shadow-copy engine).
--   ORDER="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase18 phase19 phase20 phase21 phase22 phase23 phase24 phase25 phase26 phase27 phase28 phase40 phase41 phase42 phase43 phase44 phase45 phase46 phase47 phase48" bash tests/sql/build_fresh_db.sh a48db
--   psql -h /tmp -p 5544 -U postgres -d a48db -qAt -f supabase/phase48_test.sql | grep -E 'FAIL|RESULT'
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
insert into user_locations values (:'s',1),(:'k',2) on conflict do nothing;

\echo == T0 shape
select tt.chk('T0 seven domains seeded, app path is primary by default', (select count(*) from path_domains)=7 and (select count(*) from path_domains where default_primary='a')=7
  and path_primary('payroll',0)='a' and path_primary('expense',0)='a' and path_primary('stock_issue',1)='a' and path_primary('production',1)='a' and path_primary('owner_money',1)='a');
select tt.chk('T0 both paths open by default', path_allowed('payroll',1,'a') and path_allowed('payroll',1,'b') and path_allowed('stock_issue',1,'a') and path_allowed('stock_issue',1,'b'));
select tt.chk('T0 tables have RLS, no write grants', (select count(*) from pg_class where relname in ('path_domains','path_switch','shadow_links') and relrowsecurity)=3
  and not has_table_privilege('authenticated','path_switch','insert') and not has_table_privilege('authenticated','shadow_links','insert') and not has_table_privilege('authenticated','shadow_links','update') and not has_table_privilege('authenticated','path_domains','update'));
select tt.chk('T0 internals closed; anon has nothing', not has_function_privilege('authenticated','public.path_guard(text,int,text)','execute') and not has_function_privilege('authenticated','public.shadow_link_add(text,int,text,text,text,text,text)','execute')
  and not has_function_privilege('authenticated','public.is_shadow(text,text)','execute') and not has_function_privilege('authenticated','public.path_winner(text,int,text)','execute')
  and not has_function_privilege('anon','public.path_switch_set(text,int,boolean,boolean,text,text)','execute') and not has_function_privilege('anon','public.path_cfg(text,int)','execute'));

\echo == T1 switch: owner only, a place row beats the all-places row
select tt.as(:'s');
select tt.err('T1 manager cannot set a switch', $$select path_switch_set('payroll',0,false,true)$$, 'not allowed');
select tt.err('T1 manager cannot read the owner screen', $$select path_switches()$$, 'not allowed');
select tt.as(:'o');
select tt.err('T1 missing flag', $$select path_switch_set('payroll',0,null,true)$$, 'bad_mode');
select tt.err('T1 bad primary', $$select path_switch_set('payroll',0,true,true,'both')$$, 'bad_primary');
select tt.err('T1 unknown domain', $$select path_switch_set('nope',0,true,true)$$, 'unknown_domain');
select tt.err('T1 unknown place', $$select path_switch_set('payroll',9999,true,true)$$, 'unknown_location');
select path_switch_set('stock_issue',0,false,true,'b')->'to'->>'primary' as r1 \gset
select tt.chk('T1 all-places: stock_issue screen locked, form primary', :'r1'='b' and not path_allowed('stock_issue',1,'a') and path_allowed('stock_issue',1,'b') and path_primary('stock_issue',2)='b');
select path_switch_set('stock_issue',2,true,false,null,'closed for audit')->'to'->>'primary' as r2 \gset
select tt.chk('T1 place 2 row beats all-places; null primary = domain default', :'r2'='a' and path_allowed('stock_issue',2,'a') and not path_allowed('stock_issue',2,'b') and not path_allowed('stock_issue',1,'a'));
select tt.chk('T1 placeless call uses the all-places row', path_primary('stock_issue',null)='b' and not path_allowed('stock_issue',null,'a'));
select tt.chk('T1 path_switches lists 7 domains with the place override', jsonb_array_length(path_switches())=7
  and (select jsonb_array_length(x->'places') from jsonb_array_elements(path_switches()) x where x->>'domain'='stock_issue')=1);
select tt.chk('T1 audit_log recorded the switch change', exists (select 1 from audit_log where table_name='path_switch'));

\echo == T2 guard and winner
select tt.err('T2 guard refuses a locked path', $$select path_guard('stock_issue',1,'a')$$, 'path_locked');
select tt.err('T2 guard bad path', $$select path_guard('stock_issue',1,'c')$$, 'bad_path');
do $$ begin perform path_guard('stock_issue',1,'b'); perform tt.chk('T2 guard passes an open path', true); exception when others then perform tt.chk('T2 guard passes an open path', false); end $$;
select tt.chk('T2 winner: primary=b -> the incoming form wins, an incoming screen record loses', path_winner('stock_issue',1,'b')='incoming' and path_winner('stock_issue',1,'a')='existing');
select tt.chk('T2 winner: default a -> the incoming app record wins', path_winner('payroll',1,'a')='incoming' and path_winner('payroll',1,'b')='existing');
select path_switch_set('payroll',0,true,true,'first') is not null as pf \gset
select tt.chk('T2 winner: first -> the earlier record always wins', path_winner('payroll',1,'a')='existing' and path_winner('payroll',1,'b')='existing');

\echo == T3 shadow engine
select shadow_link_add('payroll',1,'payroll_runs','R1','entries:02-2','E1','app payroll wins') as l1 \gset
select tt.chk('T3 link created confirmed', (select state from shadow_links where id=:l1)='confirmed');
select tt.chk('T3 same link again is idempotent (same id, one row)', shadow_link_add('payroll',1,'payroll_runs','R1','entries:02-2','E1')=:l1 and (select count(*) from shadow_links where primary_id='R1')=1);
select tt.chk('T3 is_shadow true for the form, false for the primary', is_shadow('entries:02-2','E1') and not is_shadow('payroll_runs','R1'));
select tt.err('T3 a shadow cannot become a primary', $$select shadow_link_add('payroll',1,'entries:02-2','E1','x','X1')$$, 'primary_is_already_a_shadow');
select tt.err('T3 a primary cannot become a shadow', $$select shadow_link_add('payroll',1,'payroll_runs','R2','payroll_runs','R1')$$, 'shadow_is_already_a_primary');
select tt.chk('T3 several primaries may share one shadow (a day of quick entries -> one voucher)', shadow_link_add('payroll',1,'payroll_runs','R2','entries:02-2','E1') is not null and is_shadow('entries:02-2','E1'));
select tt.err('T3 the same pair twice is idempotent: no second row', $$select 1/(case when (select count(*) from shadow_links where primary_id='R2')=1 then 0 else 1 end)$$, 'division');
select tt.err('T3 self shadow', $$select shadow_link_add('payroll',1,'a','1','a','1')$$, 'self_shadow');
select tt.err('T3 unknown domain', $$select shadow_link_add('zzz',1,'a','1','b','2')$$, 'unknown_domain');
select shadow_link_add('expense',1,'day_book_quick','Q1','entries:10-2',null,'day end') as l2 \gset
select tt.chk('T3 pending shadow without a record', (select state from shadow_links where id=:l2)='pending' and not is_shadow('entries:10-2','E9'));
select tt.err('T3 confirm needs the shadow id', format($$select shadow_confirm(%s)$$,:l2), 'shadow_id_needed');
select tt.as(:'k');
select tt.err('T3 a manager of ANOTHER place cannot confirm', format($$select shadow_confirm(%s,'E9')$$,:l2), 'not allowed');
select tt.as(:'s');
select shadow_confirm(:l2,'E9')->>'state' as r3 \gset
select tt.chk('T3 manager of the place confirms with one call', :'r3'='confirmed' and is_shadow('entries:10-2','E9'));
select tt.chk('T3 confirm again is a no-op', (shadow_confirm(:l2,'E9')->>'noop')='true');
select tt.err('T3 manager cannot void', format($$select shadow_void(%s,'x')$$,:l2), 'not allowed');
select tt.as(:'o');
select tt.err('T3 void needs a note', format($$select shadow_void(%s,' ')$$,:l2), 'note_needed');
select shadow_void(:l2,'wrong link')->>'state' as r4 \gset
select tt.chk('T3 void works, shadow released', :'r4'='void' and not is_shadow('entries:10-2','E9'));
select tt.chk('T3 after void the record can be linked again', shadow_link_add('expense',1,'day_book_quick','Q2','entries:10-2','E9') is not null);

\echo == T4 trail is append-only
select tt.err('T4 delete refused', $$delete from shadow_links$$, 'append_only');
select tt.err('T4 changing the primary refused', format($$update shadow_links set primary_id='ZZ' where id=%s$$,:l1), 'append_only');
select tt.err('T4 voiding back to confirmed refused', format($$update shadow_links set state='confirmed' where id=%s$$,:l2), 'append_only');

\echo == T5 reports
select tt.as(:'s');
select tt.err('T5 manager needs a place', $$select shadow_report()$$, 'not allowed');
select tt.err('T5 manager of another place refused', $$select shadow_report(null,2)$$, 'not allowed');
select tt.chk('T5 manager sees own place counts', (shadow_report(null,1)->'counts'->>'payroll:confirmed')='2');
select tt.err('T5 manager cannot run count-once check', $$select shadow_count_once_check()$$, 'not allowed');
select tt.as(:'o');
select tt.chk('T5 owner pending list empty, counts present', jsonb_array_length(shadow_report('expense',null)->'pending')=0 and (shadow_report('expense',null)->'counts'->>'expense:void')='1');
select tt.chk('T5 count-once clean at first', jsonb_array_length(shadow_count_once_check()->'shadow_in_journal')=0 and jsonb_array_length(shadow_count_once_check()->'both_roles')=0);
insert into journal_entries (entry_date, location_id, source_type, source_id, memo) values (current_date, 1, 'entries:02-2', 'E1', 'test double count');
select tt.chk('T5 count-once check finds a shadow that reached the journal', jsonb_array_length(shadow_count_once_check()->'shadow_in_journal')>=1);

\echo == T6 paste twice safe
select tt.chk('T6 still 7 domains, switch kept', (select count(*) from path_domains)=7 and path_allowed('stock_issue',2,'a') and not path_allowed('stock_issue',2,'b'));

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
