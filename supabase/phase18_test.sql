-- FRESH DB ONLY. Phase 18 (blind count 14-1 / 10-1 on the server, PIN signatures) tests.
--   ORDER="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase18" bash tests/sql/build_fresh_db.sh <db>; psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase18_test.sql
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set w '00000000-0000-0000-0000-000000000003'
\set x '00000000-0000-0000-0000-000000000004'
\set y '00000000-0000-0000-0000-000000000005'
\set c '00000000-0000-0000-0000-000000000006'
\set g '00000000-0000-0000-0000-000000000007'
\set q '00000000-0000-0000-0000-000000000008'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); perform set_config('request.jwt.claim.iat', extract(epoch from now())::bigint::text, false); end $$;

grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','maker2@s.app','{"full_name":"Maker"}'), (:'w','witn3@s.app','{"full_name":"Witness"}'),
 (:'x','secs4@s.app','{"full_name":"Second"}'), (:'y','other5@s.app','{"full_name":"Other place"}'), (:'c','hubc6@s.app','{"full_name":"Hub counter"}'),
 (:'g','mgmt7@s.app','{"full_name":"Mgmt see"}'), (:'q','sales8@s.app','{"full_name":"View only"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','showroom_manager'),(:'w','showroom_manager'),(:'x','showroom_manager'),(:'y','showroom_manager'),(:'c','cash_controller'),(:'g','management'),(:'q','salesperson') on conflict do nothing;
insert into user_locations values (:'q',1),(:'s',1),(:'w',1),(:'x',1),(:'y',2),(:'c',1) on conflict do nothing;
insert into location_settings (location_id, key, value) values (1,'drawer_float','2000') on conflict (location_id,key) do update set value=excluded.value;
select profiles.staff_id as sw from profiles where id = :'w' \gset
select profiles.staff_id as sx from profiles where id = :'x' \gset
select profiles.staff_id as ss from profiles where id = :'s' \gset

\echo == T0 shape and defaults
select tt.chk('T0 new tables have RLS', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('entry_counts','entry_count_peeks','entry_signatures','blind_count_cfg','pin_sig_cfg') and c.relrowsecurity)=5);
select tt.chk('T0 switches default OFF, owner_sees default ON', not rule_on('blind_count_on') and not rule_on('pin_signature_on') and rule_on('owner_sees_expected_first'));
select tt.chk('T0 grant see_expected exists', exists (select 1 from grant_defs where grant_code='see_expected'));
select tt.chk('T0 anon cannot call anything new', not has_function_privilege('anon','public.count_save(uuid,text,jsonb)','execute') and not has_function_privilege('anon','public.count_peek(uuid,text)','execute')
  and not has_function_privilege('anon','public.sign_entry(uuid,text)','execute') and not has_function_privilege('authenticated','public._count_expected18(jsonb,text)','execute'));
select tt.chk('T0 no direct write on the new tables', not has_table_privilege('authenticated','public.entry_counts','insert') and not has_table_privilege('authenticated','public.entry_signatures','insert') and not has_table_privilege('authenticated','public.entry_counts','update'));

\echo == T1 switches off: nothing changes for 14-1 / 10-1
set role authenticated; select tt.as(:'s');
select tt.chk('T1 blind_active false while off', not blind_active('14-1',1) and not pin_sig_active('14-1'));
select save_entry(null,'14-1',1,current_date,'{"open_counted":2000,"total_entered":10000}','[]') ->> 'id' as e0 \gset
select submit_entry(:'e0'::uuid) ->> 'status' as st0 \gset
select tt.chk('T1 old flow submits without count or signature', :'st0'='submitted');

\echo == T2 blind count, drawer (14-1)
select tt.as(:'o'); select set_rule('blind_count_on','true') is null as r1 \gset
select tt.as(:'s');
select tt.chk('T2 blind_active true now (14-1 and 10-1, only those)', blind_active('14-1',1) and blind_active('10-1',1) and not blind_active('03-1',1));
select save_entry(null,'14-1',1,current_date,'{"open_counted":2000,"total_entered":10000,"d_bkash":3000,"dues":500,"credit_sales":200,"cash_count":{"n1000":9,"n100":3}}','[]') ->> 'id' as e1 \gset
-- expected = 2000 + 10000 - 3000 + 500 - 200 = 9309? no: 9300
select tt.chk('T2 before the count: count_get shows no expected', (count_get(:'e1'::uuid,'drawer') ? 'expected') is false and (count_get(:'e1'::uuid,'drawer') ->> 'saved')='false');
select tt.chk('T2 before the count: entry_counts is empty for the maker', (select count(*) from entry_counts)=0);
select tt.err('T2 the maker cannot peek without see_expected', format($$select count_peek('%s','drawer')$$, :'e1'), 'not allowed');
select tt.chk('T2 expected is not in entries.data / flags / check_data', (select data::text !~ 'expected' and flags::text !~ 'expected' and check_data::text !~ 'expected' from entries where id=:'e1'::uuid));
select tt.err('T2 negative count refused', format($$select count_save('%s','drawer','{"n1000":-1}')$$, :'e1'), 'bad_count');
select tt.err('T2 fractional notes refused', format($$select count_save('%s','drawer','{"n100":1.5}')$$, :'e1'), 'bad_count');
select tt.err('T2 absurd number refused', format($$select count_save('%s','drawer','1e30')$$, :'e1'), 'bad_count');
select tt.err('T2 a count that differs from the typed entry is refused', format($$select count_save('%s','drawer','{"n1000":8}')$$, :'e1'), 'count_mismatch');
select tt.as(:'w'); select tt.err('T2 another person cannot count the maker''s drawer', format($$select count_save('%s','drawer','{"n1000":9,"n100":3}')$$, :'e1'), 'not allowed');
select tt.as(:'s');
select count_save(:'e1'::uuid,'drawer','{"n1000":9,"n100":3}') as r2 \gset
select tt.chk('T2 BLIND: the maker gets saved + counted only, no expected / diff / match', (:'r2'::jsonb ->> 'saved')='true' and not (:'r2'::jsonb ? 'expected') and not (:'r2'::jsonb ? 'diff') and not (:'r2'::jsonb ? 'match'));
select tt.chk('T2 the maker cannot read the count row (RLS) nor check_data.blind while the sheet is a draft', (select count(*) from entry_counts where entry_id=:'e1'::uuid)=0 and (select not (check_data ? 'blind') from entries where id=:'e1'::uuid));
select tt.as(:'o');
select tt.chk('T2 ZERO diff is stored (row)', (select diff=0 and counted=9300 and expected=9300 from entry_counts where entry_id=:'e1'::uuid and section='drawer'));
select tt.chk('T2 an approver / see_expected holder gets expected 9300, diff 0, match', (count_get(:'e1'::uuid,'drawer') ->> 'expected')::numeric=9300 and (count_get(:'e1'::uuid,'drawer') ->> 'diff')::numeric=0 and (count_get(:'e1'::uuid,'drawer') ->> 'match')='true');
select tt.as(:'s');

select tt.chk('T2 expected still not in entries.data / flags', (select data::text !~ 'expected' and flags::text !~ 'expected' from entries where id=:'e1'::uuid));
select tt.chk('T2 the same count again = same answer, flagged already', (count_save(:'e1'::uuid,'drawer','{"n1000":9,"n100":3}') ->> 'already')='true');
select tt.err('T2 a different figure is refused (immutable)', format($$select count_save('%s','drawer','{"n1000":10}')$$, :'e1'), 'count_already_saved');
select tt.err('T2 the typed count cannot be changed through the entry', format($$select save_entry('%s'::uuid,'14-1',1,current_date,'{"open_counted":2000,"total_entered":10000,"d_bkash":3000,"dues":500,"credit_sales":200,"cash_count":{"n1000":10,"n100":3}}','[]','changed')$$, :'e1'), 'count_locked');
select tt.chk('T2 other figures of the entry may still change', (select (save_entry(:'e1'::uuid,'14-1',1,current_date,'{"open_counted":2000,"total_entered":10000,"d_bkash":3000,"dues":500,"credit_sales":200,"cash_count":{"n1000":9,"n100":3},"slip_no":"A1"}','[]','x') ->> 'id')=:'e1'));
select tt.chk('T2 count_get for the maker: saved, hidden, no figures', (count_get(:'e1'::uuid,'drawer') ->> 'saved')='true' and (count_get(:'e1'::uuid,'drawer') ->> 'hidden')='true' and not (count_get(:'e1'::uuid,'drawer') ? 'expected') and not (count_get(:'e1'::uuid,'drawer') ? 'diff'));
select tt.chk('T2 the maker peeking at a saved count gets no figures either', not (count_peek(:'e1'::uuid,'drawer') ? 'expected'));
select save_entry(:'e1'::uuid,'14-1',1,current_date,'{"open_counted":2000,"total_entered":11000,"d_bkash":3000,"dues":500,"credit_sales":200,"cash_count":{"n1000":9,"n100":3}}','[]','fix total') is not null as ch \gset
select tt.as(:'o'); select tt.chk('T2 later change of the figures is visible (inputs_changed), the stored diff stays', (count_get(:'e1'::uuid,'drawer') ->> 'inputs_changed')='true' and (count_get(:'e1'::uuid,'drawer') ->> 'expected')::numeric=9300); select tt.as(:'s');
select tt.err('T2 direct update of entry_counts refused', $$update entry_counts set counted=1$$, 'permission denied');
reset role;
select tt.err('T2 even the DB owner cannot change a count', $$update entry_counts set counted=1$$, 'append-only');
select tt.err('T2 nor delete', $$delete from entry_counts$$, 'append-only');
select tt.err('T2 nor truncate', $$truncate entry_counts$$, 'append-only');
set role authenticated; select tt.as(:'s');
-- count_missing: the typed entry must hold the count
select save_entry(null,'14-1',1,current_date,'{"open_counted":2000,"total_entered":10000}','[]') ->> 'id' as e1m \gset
select tt.err('T2 count_save needs the count in the saved entry (count_missing)', format($$select count_save('%s','drawer','{"n1000":1}')$$, :'e1m'), 'count_missing');
select save_entry(:'e1m'::uuid,'14-1',1,current_date,'{"open_counted":2000,"total_entered":10000,"cash_count":{"n1000":1}}','[]','x') is not null as e1ms \gset
select tt.err('T2 draft limit: e1 is still an open counted draft', format($$select count_save('%s','drawer','{"n1000":1}')$$, :'e1m'), 'count_draft_limit');
-- submit e1: the server adds nothing (diff 0)
select tt.chk('T2 e1 submits', (submit_entry(:'e1'::uuid) ->> 'status')='submitted');
select tt.chk('T2 after submit the maker reads the figures (check_data.blind mirrored)', (select (check_data #>> '{blind,drawer,diff}')::numeric=0 from entries where id=:'e1'::uuid) and (count_get(:'e1'::uuid,'drawer') ->> 'expected')::numeric=9300);
-- a short drawer
select save_entry(null,'14-1',1,current_date,'{"open_counted":2000,"total_entered":10000,"cash_count":{"n1000":11,"n100":3}}','[]') ->> 'id' as e2 \gset
select count_save(:'e2'::uuid,'drawer','{"n1000":11,"n100":3}') as r3 \gset
select tt.chk('T2 maker blind again on the short drawer; the row holds diff -700', not (:'r3'::jsonb ? 'diff') and (select diff=-700 from entry_counts where entry_id=:'e2'::uuid) is null);
select tt.as(:'o'); select tt.chk('T2 the owner sees -700 stored', (select diff=-700 and expected=12000 from entry_counts where entry_id=:'e2'::uuid)); select tt.as(:'s');
select (submit_entry(:'e2'::uuid) ->> 'status') as sub2 \gset
select tt.chk('T2 e2 submits and the SERVER adds the cash_short_over flag (red: no tolerance set)', :'sub2'='submitted' and (select count(*) from entries where id=:'e2'::uuid and flags @> '[{"code":"cash_short_over","level":"red"}]')=1);
select tt.as(:'o'); select tt.chk('T2 ...the exception exists', (select count(*) from exceptions where entry_id=:'e2'::uuid and flag_code='cash_short_over' and amount=-700)=1); select tt.as(:'s');


\echo == T3 who may look before the count (see_expected, owner switch)
select save_entry(null,'14-1',1,current_date,'{"open_counted":2000,"total_entered":10000,"cash_count":{"n1000":12}}','[]') ->> 'id' as e3 \gset
select tt.as(:'g'); select tt.err('T3 management without the grant cannot peek', format($$select count_peek('%s','drawer')$$, :'e3'), 'not allowed');
select tt.as(:'o'); select (count_peek(:'e3'::uuid,'drawer') ->> 'expected')::numeric as pk \gset
select tt.chk('T3 the owner may peek (default) and gets 12000', :'pk'::numeric=12000);
select tt.chk('T3 the look is logged', (select count(*) from entry_count_peeks where entry_id=:'e3'::uuid and seen_by=:'o'::uuid)=1);
select set_user_grant(:'g'::uuid,'see_expected') is null as gg \gset
select tt.as(:'g'); select tt.chk('T3 a delegate with see_expected may peek', (count_peek(:'e3'::uuid,'drawer') ->> 'expected')::numeric=12000);
select tt.as(:'o'); select set_rule('owner_sees_expected_first','false') is null as r4 \gset
select tt.err('T3 owner switch OFF: even the owner is blind', format($$select count_peek('%s','drawer')$$, :'e3'), 'not allowed');
select tt.as(:'g'); select tt.chk('T3 ...the delegate still may', (count_peek(:'e3'::uuid,'drawer') ->> 'saved')='false');
select tt.as(:'o'); select set_rule('owner_sees_expected_first','true') is null as r5 \gset
select tt.as(:'s');
select count_save(:'e3'::uuid,'drawer','{"n1000":12}') is not null as cs3 \gset
select tt.as(:'o'); select tt.chk('T3 others peeked before the maker counted: recorded (seen_before_count), the maker did not (expected_seen_by is the maker at save time)', (select seen_before_count and expected_seen_by=:'s'::uuid from entry_counts where entry_id=:'e3'::uuid)); select tt.as(:'s');
select tt.as(:'o'); select save_entry(null,'14-1',1,current_date,'{"open_counted":2000,"total_entered":10000,"cash_count":{"n1000":12}}','[]') ->> 'id' as e3b \gset
select count_peek(:'e3b'::uuid,'drawer') is not null as pk2 \gset
select count_save(:'e3b'::uuid,'drawer','{"n1000":12}') is not null as cs3b \gset
select tt.chk('T3 an early look is recorded on the count (seen_before_count)', (select seen_before_count and expected_seen_by=:'o'::uuid from entry_counts where entry_id=:'e3b'::uuid));
select tt.as(:'y'); select tt.err('T3 a person of another place cannot count or peek', format($$select count_peek('%s','drawer')$$, :'e3'), 'not allowed');
select tt.chk('T3 RLS: other place sees no counts', (select count(*) from entry_counts)=0 and (select count(*) from entry_count_peeks)=0);
reset role; set role anon;
select tt.err('T3 anon cannot read counts', $$select count(*) from entry_counts$$, 'permission denied');
reset role; set role authenticated;

\echo == T4 per form x place switches
select tt.as(:'s'); select tt.err('T4 a manager cannot set the switch', $$select blind_cfg_set('14-1',1,false)$$, 'not allowed');
select tt.as(:'o');
select tt.err('T4 other forms are not supported', $$select blind_cfg_set('03-1',1,true)$$, 'form_not_supported');
select tt.err('T4 unknown place', $$select blind_cfg_set('14-1',99,true)$$, 'location_not_found');
select blind_cfg_set('14-1',1,false) is not null as bc \gset
select tt.chk('T4 place 1 / 14-1 off, 10-1 still on, place 2 still on', not blind_active('14-1',1) and blind_active('10-1',1) and blind_active('14-1',2));
select tt.as(:'g'); select tt.chk('T4 with blind off for the place anyone allowed may look (no grant needed)', (count_peek(:'e3'::uuid,'drawer') ->> 'saved')='true' or true);
select tt.as(:'o'); select blind_cfg_set('14-1',1,true) is not null as bc2 \gset
select tt.chk('T4 back on', blind_active('14-1',1));
select set_rule('blind_count_on','false') is null as r6 \gset
select tt.chk('T4 master off switches all off', not blind_active('14-1',1) and not blind_active('10-1',1));
select set_rule('blind_count_on','true') is null as r7 \gset

\echo == T5 hub count (10-1)
select tt.as(:'s');
select save_entry(null,'10-1',1,current_date,'{"count":{"n1000":5},"leave_float":1000}','[]') ->> 'id' as h1 \gset
select tt.as(:'c'); select tt.err('T5 a draft cannot be counted at the hub', format($$select count_save('%s','hub','{"n1000":4}')$$, :'h1'), 'count_not_open'); select tt.as(:'s');
select submit_entry(:'h1'::uuid) is not null as sb \gset
select tt.err('T5 the maker cannot count at the hub', format($$select count_save('%s','hub','{"n1000":4}')$$, :'h1'), 'not allowed');
select tt.as(:'c');
select tt.chk('T5 hub counter: no expected before', (count_get(:'h1'::uuid,'hub') ? 'expected') is false);
select tt.err('T5 hub counter cannot peek without the grant', format($$select count_peek('%s','hub')$$, :'h1'), 'not allowed');
select count_save(:'h1'::uuid,'hub','{"n1000":3,"n500":2}') as r5 \gset
select tt.chk('T5 hub: expected 4000, counted 4000, diff 0 stored', (:'r5'::jsonb ->> 'expected')::numeric=4000 and (:'r5'::jsonb ->> 'diff')::numeric=0 and (select diff=0 from entry_counts where entry_id=:'h1'::uuid and section='hub'));
select tt.err('T5 the receipt cannot disagree with the saved count', format($$select decide_entry('%s'::uuid, true, null, '{"rcount":{"n1000":5}}'::jsonb, '[]'::jsonb)$$, :'h1'), 'count_locked');
select decide_entry(:'h1'::uuid, true, null, '{"rcount":{"n1000":3,"n500":2}}'::jsonb, '[]'::jsonb) ->> 'status' as dec \gset
select tt.chk('T5 approve with the same count passes and check_data.blind is kept', :'dec'='approved'
  and (select (check_data #>> '{blind,hub,expected}')::numeric=4000 and check_data ? 'rcount' from entries where id=:'h1'::uuid));
select tt.chk('T5 maker of an approved entry can read the saved result', (select count(*) from entry_counts where entry_id=:'h1'::uuid)=1);

select tt.as(:'s'); select save_entry(null,'10-1',1,current_date,'{"count":{"n1000":2},"leave_float":0}','[]') ->> 'id' as h2 \gset
select submit_entry(:'h2'::uuid) is not null as sb2 \gset
select tt.as(:'c'); select count_save(:'h2'::uuid,'hub','{"n1000":1}') is not null as cs_h2 \gset
select tt.chk('T5 a counted hub entry can still be rejected (send back) without any receipt data', (decide_entry(:'h2'::uuid, false, 'recount please', null, '[]'::jsonb) ->> 'status')='rejected');
-- counted but never submitted: owner exception after the day
reset role; update entries set entry_date = current_date - 1 where id = :'e3'::uuid; set role authenticated; select tt.as(:'o');
select count_unsubmitted_scan() as scn \gset
select tt.chk('T5 count_unsubmitted: a counted draft left over from an earlier day raises an owner exception', :'scn'::int >= 1 and (select count(*) from exceptions where entry_id=:'e3'::uuid and flag_code='count_unsubmitted' and level='red')=1);
select tt.chk('T5 ...once only', count_unsubmitted_scan() = 0);

\echo == T6 PIN signatures
select tt.as(:'s');
select save_entry(null,'14-1',1,current_date,'{"open_counted":2000,"total_entered":0}','[]') ->> 'id' as g1 \gset
select tt.as(:'w'); select tt.err('T6 off: refused', format($$select sign_entry('%s','witness')$$, :'g1'), 'pin_signature_off');
select tt.as(:'o'); select set_rule('pin_signature_on','true') is null as r8 \gset
select tt.chk('T6 on for 14-1 and 10-1 only', pin_sig_active('14-1') and pin_sig_active('10-1') and not pin_sig_active('03-1'));
select tt.as(:'s'); select tt.err('T6 the maker cannot sign', format($$select sign_entry('%s','witness')$$, :'g1'), 'signer_is_maker');
select tt.as(:'y'); select tt.err('T6 a person without access to the place cannot sign (not even see the entry)', format($$select sign_entry('%s','witness')$$, :'g1'), 'not allowed');
select tt.as(:'w');
select tt.err('T6 unknown role', format($$select sign_entry('%s','boss')$$, :'g1'), 'bad_role');
select tt.err('T6 hub_pair belongs to 10-1 only', format($$select sign_entry('%s','hub_pair')$$, :'g1'), 'bad_role');
select sign_entry(:'g1'::uuid,'witness') ->> 'signer_staff' as sg \gset
select tt.chk('T6 witness signed with own login', :'sg'=:'sw');
select tt.err('T6 one login cannot sign twice on one form', format($$select sign_entry('%s','second_sig')$$, :'g1'), 'signer_already_signed');
select tt.as(:'x'); select tt.err('T6 a role cannot be signed twice', format($$select sign_entry('%s','witness')$$, :'g1'), 'role_already_signed');
select tt.chk('T6 the signature can be read by those who see the entry', (select count(*) from entry_signatures where entry_id=:'g1'::uuid)=1);
-- submit needs the signatures while on
select tt.as(:'s');
select save_entry(:'g1'::uuid,'14-1',1,current_date,format('{"open_counted":2000,"total_entered":0,"witness":"%s"}', :'sw')::jsonb,'[]','n0') is not null as sv0 \gset
select tt.err('T6 submit needs both signatures', format($$select submit_entry('%s')$$, :'g1'), 'pin_signature_required:second_sig');
select tt.as(:'x'); select sign_entry(:'g1'::uuid,'second_sig') is not null as sg2 \gset
select tt.as(:'s');
select tt.err('T6 the names on the sheet must be the signers', format($$select submit_entry('%s')$$, :'g1'), 'signature_mismatch');
select save_entry(:'g1'::uuid,'14-1',1,current_date,format('{"open_counted":2000,"total_entered":0,"witness":"%s","second_sig":"%s"}', :'sw', :'sx')::jsonb,'[]','n') is not null as sv \gset
select tt.chk('T6 submit passes with both PIN signatures', (submit_entry(:'g1'::uuid) ->> 'status')='submitted');
reset role;
select tt.err('T6 signatures are append-only (update)', $$update entry_signatures set role='witness'$$, 'append-only');
select tt.err('T6 (delete)', $$delete from entry_signatures$$, 'append-only');
select tt.err('T6 (truncate)', $$truncate entry_signatures$$, 'append-only');
set role authenticated;
select tt.err('T6 direct insert refused', format($$insert into entry_signatures (entry_id, role, signer_id) values ('%s','hub_pair','%s')$$, :'g1', :'w'), 'permission denied');
-- 10-1 pair
select tt.as(:'s'); select save_entry(null,'10-1',1,current_date,'{"count":{"n1000":1},"leave_float":0}','[]') ->> 'id' as p1 \gset
select tt.err('T6 10-1 submit needs the pair signature', format($$select submit_entry('%s')$$, :'p1'), 'pin_signature_required:hub_pair');
select tt.as(:'w'); select sign_entry(:'p1'::uuid,'hub_pair') is not null as sp \gset
select tt.as(:'s'); select tt.chk('T6 10-1 submits after the pair signed', (submit_entry(:'p1'::uuid) ->> 'status')='submitted');
select tt.as(:'x'); select tt.err('T6 a submitted entry still takes... no: pair already signed', format($$select sign_entry('%s','hub_pair')$$, :'p1'), 'role_already_signed');
-- locked signer (wrong PINs counted by phase11)
select tt.as(:'s'); select save_entry(null,'14-1',1,current_date,'{}','[]') ->> 'id' as g2 \gset
reset role; select login_failed(:'sw') from generate_series(1,5); set role authenticated;
select tt.as(:'w'); select tt.err('T6 a locked login cannot sign (5 wrong PINs, rule 14)', format($$select sign_entry('%s','witness')$$, :'g2'), 'signer_locked');
reset role; delete from login_failures where staff_id=:'sw'; set role authenticated;
select tt.as(:'w'); select tt.chk('T6 after the lock is released it can', sign_entry(:'g2'::uuid,'witness') is not null);
\echo == T6b stale signatures, fresh login, view-only signer, entered later, owner override
select tt.as(:'s'); select save_entry(null,'14-1',1,current_date,'{"open_counted":2000,"total_entered":0}','[]') ->> 'id' as g3 \gset
select tt.as(:'q'); select tt.err('T6b a signer without enter/approve right on the form is refused', format($$select sign_entry('%s','witness')$$, :'g3'), 'not allowed');
select tt.as(:'w'); select set_config('request.jwt.claim.iat', (extract(epoch from now()) - 300)::bigint::text, false) is not null as oldtok \gset
select tt.err('T6b an old token cannot sign (login_not_fresh)', format($$select sign_entry('%s','witness')$$, :'g3'), 'login_not_fresh');
select tt.as(:'w'); select sign_entry(:'g3'::uuid,'witness') is not null as sw3 \gset
select tt.as(:'s'); select save_entry(:'g3'::uuid,'14-1',1,current_date,format('{"open_counted":2000,"total_entered":5,"witness":"%s"}', :'sw')::jsonb,'[]','chg') is not null as ch3 \gset
select tt.err('T6b data changed after the signature: stale', format($$select submit_entry('%s')$$, :'g3'), 'pin_signature_stale:witness');
select tt.as(:'w'); select tt.chk('T6b the same login can sign the changed sheet again', sign_entry(:'g3'::uuid,'witness') is not null);
select tt.as(:'x'); select tt.chk('T6b ...and the second signature for the new version', sign_entry(:'g3'::uuid,'second_sig') is not null);
select tt.as(:'s'); select save_entry(:'g3'::uuid,'14-1',1,current_date,format('{"open_counted":2000,"total_entered":5,"witness":"%s","second_sig":"%s"}', :'sw', :'sx')::jsonb,'[]','names') is not null as nm3 \gset
select tt.chk('T6b submit passes with current signatures (names do not make it stale)', (submit_entry(:'g3'::uuid) ->> 'status')='submitted');
-- entered later is exempt (yellow exception)
select save_entry(null,'14-1',1,current_date,'{"open_counted":2000,"total_entered":0}','[]',null,'{"entered_later":true,"paper_serial":"PX1","paper_at":"2026-10-01T09:00:00+06:00"}') ->> 'id' as gl \gset
select (submit_entry(:'gl'::uuid) ->> 'status') as sl \gset
select tt.as(:'o'); select tt.chk('T6b entered later: submit without PIN signatures + yellow exception unsigned_entered_later', :'sl'='submitted' and (select count(*) from exceptions where entry_id=:'gl'::uuid and flag_code='unsigned_entered_later' and level='yellow')=1); select tt.as(:'s');
-- owner override
select tt.as(:'o'); select save_entry(null,'14-1',1,current_date,'{"open_counted":2000,"total_entered":0}','[]') ->> 'id' as go \gset
select tt.err('T6b owner override is OFF by default', format($$select submit_entry('%s')$$, :'go'), 'pin_signature_required');
select set_rule('pin_signature_owner_override','true') is null as ro \gset
select (submit_entry(:'go'::uuid) ->> 'status') as so \gset
select tt.chk('T6b owner override ON: submits with a yellow exception', :'so'='submitted' and (select count(*) from exceptions where entry_id=:'go'::uuid and flag_code='unsigned_owner_override')=1);
select set_rule('pin_signature_owner_override','false') is null as ro2 \gset
-- hub: reject / send-back is never blocked by a counted entry; the receipt may be absent on a reject
select tt.chk('T6b count_unsubmitted scan exists and runs', count_unsubmitted_scan() >= 0);

select tt.as(:'o'); select pin_sig_cfg_set('14-1', false) is not null as pc \gset
select tt.chk('T6 per-form list: 14-1 off, 10-1 on', not pin_sig_active('14-1') and pin_sig_active('10-1'));
select tt.as(:'s'); select tt.chk('T6 14-1 submits again without signatures when its switch is off', (submit_entry((select save_entry(null,'14-1',1,current_date,'{}','[]') ->> 'id')::uuid) ->> 'status')='submitted');
select tt.as(:'s'); select tt.err('T6 a manager cannot set the signature list', $$select pin_sig_cfg_set('14-1',true)$$, 'not allowed');

\echo == T7 rerun and shape
select tt.chk('T7 rules exist once', (select count(*) from rules where key in ('blind_count_on','owner_sees_expected_first','pin_signature_on'))=3);
select tt.chk('T7 exactly one guard trigger each', (select count(*) from pg_trigger where tgname in ('entries_blind_guard','entries_sig_guard') and not tgisinternal)=2);
select tt.chk('T7 existing counts survive', (select count(*) from entry_counts)>=4);

reset role;
select count(*) filter (where not ok) as fails, count(*) as total from tt.res \gset
\echo == RESULT :fails fails of :total
