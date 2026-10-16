-- FRESH DB ONLY. Phase 15 (list add-rules, Other queue) tests.
--   ORDER="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15" bash tests/sql/build_fresh_db.sh <db>; psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase15_test.sql
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set p '00000000-0000-0000-0000-000000000004'
\set m '00000000-0000-0000-0000-000000000005'
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
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Sales"}'), (:'k','store3@s.app','{"full_name":"Store"}'),
 (:'p','buy4@s.app','{"full_name":"Buyer"}'), (:'m','mgr5@s.app','{"full_name":"Mgr"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','salesperson'),(:'k','storekeeper'),(:'p','purchasing'),(:'m','management') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'p',1) on conflict do nothing;

\echo == T0 shape
select tt.chk('T0 list_defs seeded for every list in option_lists, default approval', (select count(*) from list_defs)=(select count(distinct list_code) from option_lists) and not exists (select 1 from list_defs where add_rule<>'approval' or not allow_other or locked or hidden or not active));
select tt.chk('T0 new tables have RLS', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('list_defs','option_requests','list_other_entries','list_managers') and c.relrowsecurity)=4);
select tt.chk('T0 rules and grant exist', rule_on('owner_self_approve') and rule_num('list_search_min')=8 and exists (select 1 from grant_defs where grant_code='list_manage'));
select tt.chk('T0 helpers not executable by anon', not has_function_privilege('anon','public.option_add(text,text,text,text,jsonb,boolean,uuid)','execute') and not has_function_privilege('anon','public._opt_insert(text,text,text,text,jsonb)','execute')
  and not has_function_privilege('authenticated','public._opt_insert(text,text,text,text,jsonb)','execute') and not has_function_privilege('anon','public.option_other_log(text,text,jsonb)','execute'));
select tt.chk('T0 normalise: case, spaces, Bangla digits', _opt_norm(' Sweet  Box-১২ ')='sweetbox12' and _opt_lev1('roshogolla','rosogolla') and not _opt_lev1('abc','abd'));

\echo == T1 add rule OPEN: any active user adds at once
set role authenticated; select tt.as(:'o');
select list_def_set('expense_heads','{"add_rule":"open"}') is not null as ok \gset
select tt.chk('T1 owner sets rule', (select add_rule from list_defs where list_code='expense_heads')='open');
select tt.as(:'s');
select option_add('expense_heads','নতুন ভ্যান ফি','Van fee') ->> 'status' as st, (option_add('expense_heads','গাড়ির ভ্যান ফি','Car van fee') ->> 'status') as st2 \gset
select tt.chk('T1 staff adds at once under open (first add; second is similar)', :'st'='added' and :'st2'='similar');
select tt.chk('T1 value_code is slug of English name, created_by set', exists (select 1 from option_lists where list_code='expense_heads' and value_code='van_fee' and created_by=:'s'::uuid and created_at is not null));
select option_add('expense_heads','নতুন ভ্যান ফি','Van fee') ->> 'status' as st3 \gset
select tt.chk('T1 same name again -> exists, nothing added', :'st3'='exists' and (select count(*) from option_lists where list_code='expense_heads' and label_en='Van fee')=1);
select option_add('expense_heads','  VAN  FEE ',null) ->> 'status' as st4 \gset
select tt.chk('T1 normalised duplicate (case/space) -> exists', :'st4'='exists');
select option_add('expense_heads','গাড়ির ভ্যান ফি ২','Car van fee 2', null, '{}', true) ->> 'status' as st5 \gset
select tt.chk('T1 similar can be added anyway with force', :'st5'='added');
select tt.chk('T1 similar list says which', (option_similar('expense_heads','Transports',null,null)->0->>'value_code')='transport');
select tt.err('T1 empty name refused', $$select option_add('expense_heads','  ')$$, 'name_required');
select tt.err('T1 unknown list refused', $$select option_add('nope_list','x')$$, 'unknown_list');
select tt.err('T1 name too long', format($$select option_add('expense_heads',%L)$$, repeat('x',130)), 'name_too_long');

\echo == T2 RLS: nobody but the owner can write option_lists directly
select tt.err('T2 staff direct insert refused', $$insert into option_lists (list_code,value_code,label_bn) values ('expense_heads','hack','হ্যাক')$$, 'row-level security');
update option_lists set label_bn='X' where list_code='expense_heads' and value_code='transport';
select tt.chk('T2 staff direct update changes nothing', (select label_bn from option_lists where list_code='expense_heads' and value_code='transport')<>'X');
select tt.err('T2 staff cannot write list_defs', $$update list_defs set add_rule='open' where list_code='units'$$, 'permission denied');
select tt.err('T2 staff cannot call list_def_set', $$select list_def_set('units','{"add_rule":"open"}')$$, 'not allowed');
select tt.err('T2 staff cannot write requests directly', $$insert into option_requests (list_code,label_bn) values ('units','x')$$, 'permission denied');
select tt.err('T2 staff cannot write other queue directly', $$update list_other_entries set status='added'$$, 'permission denied');
select tt.err('T2 nobody deletes (staff)', $$delete from option_lists$$, 'permission denied');
reset role; select tt.err('T2 even the table owner cannot delete', 'delete from list_defs', 'nothing is deleted');
select tt.err('T2 value_code immutable', $$update option_lists set value_code='zz' where value_code='van_fee'$$, 'code is immutable');

\echo == T3 rule APPROVAL: request, person uses Other meanwhile; maker <> approver
set role authenticated; select tt.as(:'o');
select list_def_set('expense_heads','{"add_rule":"approval"}') is not null as ok \gset
select tt.as(:'s');
select option_add('expense_heads','ইন্টারনেট বিল','Internet bill', null, '{}', false, 'aaaaaaaa-0000-0000-0000-000000000001') as r1 \gset
select tt.chk('T3 staff request is pending, option not added', (:'r1'::jsonb->>'status')='requested' and not exists (select 1 from option_lists where label_en='Internet bill') and (select count(*) from option_requests where status='pending')=1);
select option_add('expense_heads','ইন্টারনেট বিল','Internet bill', null, '{}', false, 'aaaaaaaa-0000-0000-0000-000000000001') ->> 'repeat' as rep \gset
select tt.chk('T3 same client id is idempotent', :'rep'='true' and (select count(*) from option_requests)=1);
select tt.as(:'k');
select option_add('expense_heads','ইন্টারনেট বিল','Internet bill') ->> 'duplicate' as dup \gset
reset role; select id as rq1 from option_requests limit 1 \gset
select tt.chk('T3 duplicate pending request returned, not filed again', :'dup'='true' and (select count(*) from option_requests)=1);
set role authenticated; select tt.as(:'k');
select tt.err('T3 staff cannot decide', format($$select option_request_decide(%L,true)$$, :'rq1'), 'not allowed');
select tt.as(:'s');
select tt.chk('T3 requester sees own request, others do not', (select count(*) from option_requests)=1);
select tt.as(:'k'); select tt.chk('T3 other staff does not see it', (select count(*) from option_requests)=0);
-- delegation: m gets list_manage
select tt.as(:'o');
select set_user_grant(:'m'::uuid,'list_manage') is null as g \gset
select tt.as(:'m');
select tt.chk('T3 list_manage holder sees the request', (select count(*) from option_requests)=1);
select option_request_decide((select id from option_requests limit 1), true, 'ok') ->> 'value_code' as vc \gset
select tt.chk('T3 grantee approves -> option exists, value_code recorded', :'vc'='internet_bill' and exists (select 1 from option_lists where list_code='expense_heads' and value_code='internet_bill' and active) and (select status from option_requests limit 1)='approved');
select option_request_decide((select id from option_requests limit 1), false) ->> 'repeat' as rr \gset
select tt.chk('T3 deciding twice is idempotent', :'rr'='true');
-- maker <> approver for a grantee
select option_add('expense_heads','গ্যাস বিল','Gas bill') ->> 'status' as gst \gset
select tt.chk('T3 grantee under approval rule also files a request (cannot approve own)', :'gst'='requested');
select tt.err('T3 grantee cannot approve own request', format($$select option_request_decide(%L,true)$$, (select id from option_requests where status='pending' limit 1)), 'self_approval');
select tt.as(:'o');
select option_request_decide((select id from option_requests where status='pending' limit 1), false, 'no') ->> 'status' as rj \gset
select tt.chk('T3 owner rejects another person''s request, nothing added', :'rj'='rejected' and not exists (select 1 from option_lists where label_en='Gas bill'));
-- owner self approval switch
select option_add('expense_heads','পানির বিল','Water bill') ->> 'status' as ost \gset
select tt.chk('T3 owner adds directly while owner_self_approve is on', :'ost'='added');
reset role; update rules set value='false'::jsonb where key='owner_self_approve'; set role authenticated; select tt.as(:'o');
select option_add('expense_heads','বিদ্যুৎ বিল','Electric bill') ->> 'status' as ost2 \gset
select tt.chk('T3 owner_self_approve OFF: owner''s add becomes a request', :'ost2'='requested');
select tt.err('T3 owner_self_approve OFF: owner cannot approve own', format($$select option_request_decide(%L,true)$$, (select id from option_requests where status='pending' limit 1)), 'self_approval');
select tt.as(:'m');
select option_request_decide((select id from option_requests where status='pending' limit 1), true) ->> 'status' as ap2 \gset
select tt.chk('T3 a grantee can approve the owner''s request', :'ap2'='approved' and exists (select 1 from option_lists where label_en='Electric bill'));
reset role; update rules set value=null where key='owner_self_approve'; set role authenticated;

\echo == T4 rule OWNER: only owner / list manager add
select tt.as(:'o');
select list_def_set('units','{"add_rule":"owner"}') is not null as ok \gset
select tt.as(:'s');
select tt.err('T4 staff add refused under owner rule', $$select option_add('units','হালি','dozen4')$$, 'owner_only');
select tt.as(:'m');
select option_add('units','হালি','halfdozen') ->> 'status' as st \gset
select tt.chk('T4 list_manage holder adds at once under owner rule', :'st'='added');
select tt.as(:'o');
select option_add('units','কার্টন','Carton') ->> 'status' as st \gset
select tt.chk('T4 owner adds at once', :'st'='added');
-- per-list manager
select list_manager_set('units', :'p'::uuid, true) is null as lm \gset
select tt.as(:'p');
select option_add('units','গ্রস','gross') ->> 'status' as st \gset
select tt.chk('T4 per-list manager adds to that list', :'st'='added');
select tt.as(:'o'); select list_def_set('wallets','{"add_rule":"owner"}') is not null as ok \gset
select tt.as(:'p');
select tt.err('T4 per-list manager refused on another owner-rule list', $$select option_add('wallets','নতুন পে','Newpay')$$, 'owner_only');
select tt.as(:'s'); select tt.err('T4 staff cannot grant list managers', format($$select list_manager_set('units',%L,true)$$, :'s'), 'not allowed');

\echo == T5 lock / inactive list / validation
select tt.as(:'o');
select list_def_set('units','{"locked":true}') is not null as ok \gset
select tt.err('T5 locked list refuses add (even owner)', $$select option_add('units','নতুন একক','newunit')$$, 'list_locked');
reset role; select tt.err('T5 locked list refuses direct label edit (trigger)', $$update option_lists set label_bn='X' where list_code='units' and value_code='kg'$$, 'list_locked');
select tt.err('T5 locked list refuses direct insert (trigger)', $$insert into option_lists (list_code,value_code,label_bn) values ('units','zzz','z')$$, 'list_locked');
set role authenticated; select tt.as(:'o');
select list_def_set('units','{"locked":false,"active":false}') is not null as ok \gset
select tt.err('T5 inactive list refuses add', $$select option_add('units','নতুন একক','newunit')$$, 'list_inactive');
select list_def_set('units','{"active":true}') is not null as ok \gset
select tt.err('T5 bad rule refused', $$select list_def_set('units','{"add_rule":"anyone"}')$$, 'bad_value');
select tt.err('T5 bad key refused', $$select list_def_set('units','{"foo":1}')$$, 'bad_value');
select tt.err('T5 check constraint on table itself', $$update list_defs set add_rule='x' where list_code='units'$$, 'permission denied');
select list_def_set('units','{"hidden":true,"note":"tidy"}') is not null as ok \gset
select tt.chk('T5 hide + note saved', (select hidden and note='tidy' from list_defs where list_code='units'));
select list_def_set('units','{"hidden":false,"add_rule":"approval"}') is not null as ok \gset

\echo == T6 Other queue
select tt.as(:'s');
select option_other_log('expense_heads','ঠেলা ভাড়া','{"form_code":"10-2","client_id":"bbbbbbbb-0000-0000-0000-000000000001"}') as o1 \gset
select tt.chk('T6 Other logged pending with form code', (:'o1'::jsonb->>'status')='pending' and exists (select 1 from list_other_entries where text='ঠেলা ভাড়া' and form_code='10-2' and entered_by=:'s'::uuid and status='pending'));
select option_other_log('expense_heads','ঠেলা ভাড়া','{"form_code":"10-2","client_id":"bbbbbbbb-0000-0000-0000-000000000001"}') ->> 'repeat' as rep \gset
select tt.chk('T6 same client id idempotent', :'rep'='true' and (select count(*) from list_other_entries)=1);
select option_other_log('expense_heads','TRANSPORT') ->> 'status' as ex \gset
select tt.chk('T6 text equal to a listed option is not queued', :'ex'='exists' and (select count(*) from list_other_entries)=1);
select option_other_log('expense_heads','ঠেলা  ভাড়া') ->> 'status' as dupq \gset
select tt.as(:'k'); select option_other_log('expense_heads','Thela Vara') ->> 'status' as o2 \gset
select option_other_log('expense_heads','ঠেলা ভাড়া','{"form_code":"10-2"}') ->> 'status' as o3 \gset
reset role; select id as oq1 from list_other_entries limit 1 \gset
select tt.chk('T6 same text by another person queued separately', (select count(*) from list_other_entries where status='pending')=4);
set role authenticated; select tt.as(:'k');
select tt.err('T6 staff cannot resolve', format($$select option_other_resolve(%L,'reject')$$, :'oq1'), 'not allowed');
select tt.err('T6 too long', format($$select option_other_log('expense_heads',%L)$$, repeat('y',201)), 'name_too_long');
select tt.err('T6 empty', $$select option_other_log('expense_heads',' ')$$, 'name_required');
select tt.err('T6 unknown list', $$select option_other_log('zzz','abc')$$, 'unknown_list');
select tt.as(:'o');
select list_def_set('wallets','{"allow_other":false}') is not null as ok \gset
select tt.err('T6 allow_other off refuses Other', $$select option_other_log('wallets','Upay')$$, 'other_not_allowed');
select list_def_set('wallets','{"allow_other":true}') is not null as ok \gset
select tt.chk('T6 owner sees all queued entries', (select count(*) from list_other_entries)=4);
select tt.chk('T6 queue counts (owner)', (list_queue_counts()->>'other')::int=4 and (list_queue_counts()->>'requests')::int=0);
-- approve as new (resolves the same text of the other two persons too, never deletes)
select option_other_resolve((select id from list_other_entries where entered_by=:'s'::uuid and text='ঠেলা ভাড়া' order by entered_at limit 1), 'add', null, null, 'Thela hire') as rs \gset
select tt.chk('T6 owner adds Other as new option; equal texts resolved together; rows kept', (:'rs'::jsonb->>'status')='added' and (:'rs'::jsonb->>'resolved')::int=3 and (select count(*) from list_other_entries)=4
  and (select count(*) from list_other_entries where status='added' and resolved_option=(:'rs'::jsonb->>'value_code') and resolved_by=:'o'::uuid and resolved_at is not null)=3 and exists (select 1 from option_lists where list_code='expense_heads' and value_code=:'rs'::jsonb->>'value_code' and label_bn='ঠেলা ভাড়া'));
select option_other_resolve((select id from list_other_entries where status='pending' limit 1), 'merge', 'transport') as mg \gset
select tt.chk('T6 merge into an existing option', (:'mg'::jsonb->>'status')='merged' and (select resolved_option from list_other_entries where status='merged')='transport');
select option_other_log('expense_heads','tmp pending x') ->> 'status' as tp \gset
select tt.err('T6 merge into a missing option refused', format($$select option_other_resolve(%L,'merge','nope')$$, (select id from list_other_entries where text='tmp pending x')), 'bad_option');
select tt.chk('T6 nothing pending left', (select count(*) from list_other_entries where status='pending')=1 or (select count(*) from list_other_entries where status='pending')=0);
select option_other_log('expense_heads','অন্য খরচ') ->> 'status' as nn \gset
select option_other_resolve((select id from list_other_entries where text='অন্য খরচ'), 'reject', null, null, null, null, 'junk') ->> 'status' as rj \gset
select tt.chk('T6 reject keeps the row', :'rj'='rejected' and (select count(*) from list_other_entries where text='অন্য খরচ' and status='rejected')=1);
select option_other_resolve((select id from list_other_entries where text='অন্য খরচ'), 'reject') ->> 'repeat' as rp \gset
select tt.chk('T6 resolve twice is idempotent', :'rp'='true');
-- maker <> approver in the Other queue
select tt.as(:'m'); select option_other_log('expense_heads','মিশ্র খরচ') ->> 'status' as mo \gset
select tt.err('T6 grantee cannot resolve own Other', format($$select option_other_resolve(%L,'add')$$, (select id from list_other_entries where text='মিশ্র খরচ')), 'self_approval');
select tt.as(:'o'); select option_other_resolve((select id from list_other_entries where text='মিশ্র খরচ'), 'add') ->> 'status' as ok \gset
select tt.chk('T6 owner resolves a grantee''s Other', :'ok'='added');
select option_other_log('expense_heads','zap zap') ->> 'status' as zz \gset
select tt.err('T6 bad action', format($$select option_other_resolve(%L,'zap')$$, (select id from list_other_entries where text='zap zap')), 'bad_value');

\echo == T7 retire / reactivate / edit / reorder
select tt.as(:'s'); select tt.err('T7 staff cannot retire', $$select option_retire('expense_heads','transport','x')$$, 'not allowed');
select tt.as(:'m');
select tt.err('T7 retire needs a reason', $$select option_retire('expense_heads','transport','  ')$$, 'reason_required');
select option_retire('expense_heads','transport','not used any more') ->> 'status' as st \gset
select tt.chk('T7 retired: inactive, reason, who and when stamped, row still there', exists (select 1 from option_lists where list_code='expense_heads' and value_code='transport' and not active and retired_reason='not used any more' and retired_by=:'m'::uuid and retired_at is not null));
select option_retire('expense_heads','transport','again') ->> 'repeat' as rp \gset
select tt.chk('T7 retiring twice changes nothing', :'rp'='true' and (select retired_reason from option_lists where value_code='transport' and list_code='expense_heads')='not used any more');
select tt.chk('T7 a retired value is still found by the similar check', option_similar('expense_heads','Transport')->0->>'active'='false');
select option_reactivate('expense_heads','transport') is not null as ra \gset
select tt.chk('T7 reactivate clears the stamps', exists (select 1 from option_lists where value_code='transport' and list_code='expense_heads' and active and retired_at is null and retired_reason is null));
select option_update('expense_heads','transport','যাতায়াত খরচ','Transport cost') is not null as up \gset
select tt.chk('T7 edit labels; code unchanged', exists (select 1 from option_lists where value_code='transport' and list_code='expense_heads' and label_bn='যাতায়াত খরচ' and label_en='Transport cost'));
select option_reorder('expense_heads', array['repair','transport']) ->> 'n' as n \gset
select tt.chk('T7 reorder', (select sort from option_lists where list_code='expense_heads' and value_code='repair')=1 and (select sort from option_lists where list_code='expense_heads' and value_code='transport')=2);
select tt.err('T7 bad option', $$select option_update('expense_heads','nope','x')$$, 'bad_option');
select tt.as(:'s'); select tt.err('T7 staff cannot reorder', $$select option_reorder('expense_heads', array['repair'])$$, 'not allowed');
select tt.as(:'o');
select tt.chk('T7 audit log has the retire line', exists (select 1 from audit_log where table_name='option_lists' and record_id='expense_heads:transport' and detail->'new' ? 'retired_reason'));
select tt.chk('T7 audit log has request + other lines', exists (select 1 from audit_log where table_name='option_requests') and exists (select 1 from audit_log where table_name='list_other_entries') and exists (select 1 from audit_log where table_name='list_defs'));

\echo == T8 counts for a request manager, visibility
select tt.as(:'s'); select tt.err('T8 staff add on owner-rule wallets refused', $$select option_add('wallets','নতুন পে','Newpay x')$$, 'owner_only');
select tt.as(:'o'); select list_def_set('wallets','{"add_rule":"approval"}') is not null as ok \gset
select tt.as(:'s'); select option_add('wallets','নতুন পে','Newpay') ->> 'status' as st \gset
select tt.chk('T8 wallets request filed', :'st'='requested');
select tt.as(:'p');
select tt.chk('T8 per-list manager of units sees only own lists in counts', (list_queue_counts()->>'requests')::int=0);
select tt.as(:'o'); select tt.chk('T8 owner counts include wallets request', (list_queue_counts()->'lists'->'wallets'->>'requests')::int=1 and (list_queue_counts()->>'requests')::int=1);
select tt.as(:'s'); select tt.chk('T8 staff counts are zero', (list_queue_counts()->>'requests')::int=0 and (list_queue_counts()->>'other')::int=0);

\echo == T10 audit fixes
reset role;
select tt.chk('T10 norm: precomposed য় = য + nukta, ZWJ and danda ignored, NFC', _opt_norm(U&'\09DF')=_opt_norm(U&'\09AF\09BC') and _opt_norm(U&'\09A1\09BC')=_opt_norm(U&'\09DC') and _opt_norm('চা'||U&'\200C'||'য়')=_opt_norm('চায়') and _opt_norm('খরচ।')='খরচ');
set role authenticated; select tt.as(:'o'); select list_def_set('expense_heads','{"add_rule":"approval"}') is not null as ok \gset
select tt.as(:'s');
select option_add('expense_heads','এক্সট্রা খরচ','Extra cost',null,'{"limit_month":999999}') ->> 'status' as st \gset
select tt.chk('T10 non-manager''s extra is dropped from the request', :'st'='requested' and (select extra from option_requests where label_en='Extra cost')='{}');
select tt.as(:'o');
select option_request_decide((select id from option_requests where label_en='Extra cost'), true) ->> 'value_code' as vc \gset
select tt.chk('T10 approved option has no limit from the requester', (select extra from option_lists where list_code='expense_heads' and value_code=:'vc')='{}');
select option_add('marketing_heads','নতুন মার্কেটিং','New mkt',null,'{"limit_month":1200,"cat_no":"99"}') ->> 'value_code' as mv \gset
select tt.chk('T10 owner''s extra kept, cat_no stripped', (select extra from option_lists where list_code='marketing_heads' and value_code=:'mv')='{"limit_month":1200}'::jsonb);
select option_update('marketing_heads',:'mv','নতুন মার্কেটিং','New mkt',null,'{"limit_month":1500}') is not null as okx \gset
select tt.chk('T10 option_update changes extra for the owner', (select extra->>'limit_month' from option_lists where list_code='marketing_heads' and value_code=:'mv')='1500');
select tt.as(:'m');
select tt.err('T10 a list_manage holder cannot set extra', format($$select option_update('marketing_heads',%L,'x',null,null,'{"limit_month":1}')$$, :'mv'), 'not allowed');
select tt.err('T10 whitespace/punctuation-only name refused', $$select option_add('expense_heads',' - . ')$$, 'name_required');
select tt.err('T10 long name in similar refused', format($$select option_similar('expense_heads',%L)$$, repeat('z',130)), 'name_too_long');
select tt.as(:'o'); select list_def_set('expense_heads','{"add_rule":"open"}') is not null as ok \gset
select option_add('wallets','অন্য ওয়ালেট','other',null,'{}',true) ->> 'value_code' as ov \gset
select tt.chk('T10 value_code other is reserved', :'ov' is distinct from 'other' and :'ov' like 'other%');
-- Other log: ctx whitelist, size, per-user cap
select tt.as(:'s');
select option_other_log('expense_heads','টেস্ট ctx','{"form_code":"10-2","item_id":"I-001","field":"head","evil":"x","entry_id":"nope"}') as lg \gset
select tt.chk('T10 ctx keeps only whitelisted keys', (select ctx from list_other_entries where text='টেস্ট ctx')='{"form_code":"10-2","item_id":"I-001","field":"head"}'::jsonb);
select tt.err('T10 ctx over 2 KB refused', format($$select option_other_log('expense_heads','big ctx',%L::jsonb)$$, '{"field":"' || repeat('a',3000) || '"}'), 'ctx_too_large');
reset role; update rules set value='2'::jsonb where key='other_pending_cap'; set role authenticated; select tt.as(:'s');
select option_other_log('expense_heads','cap one') ->> 'status' as c1 \gset
select tt.err('T10 pending cap per user', $$select option_other_log('expense_heads','cap two')$$, 'other_queue_full');
reset role; update rules set value=null where key='other_pending_cap'; set role authenticated;
-- resolve: similar check, force, merge inactive
select tt.as(:'o');
select option_other_resolve((select id from list_other_entries where text='cap one'), 'add', null, 'ক্যাপ ওয়ান', 'cap one') ->> 'status' as r1 \gset
select tt.chk('T10 resolve add on a fresh name works', :'r1'='added');
select option_other_log('expense_heads','Cap On') ->> 'status' as l2 \gset
reset role; select tt.chk('T10 owner can log', true); set role authenticated; select tt.as(:'s');
select option_other_log('expense_heads','ক্যাপ ওয়ানে') ->> 'status' as l3 \gset
select tt.as(:'o');
select option_other_resolve((select id from list_other_entries where text='ক্যাপ ওয়ানে'), 'add', null, 'ক্যাপ ওয়ানে', null) ->> 'status' as r3 \gset
select tt.chk('T10 resolve add warns about a similar option', :'r3'='similar');
select option_other_resolve((select id from list_other_entries where text='ক্যাপ ওয়ানে'), 'add', null, 'ক্যাপ ওয়ানে', null, null, null, true) ->> 'status' as r4 \gset
select tt.chk('T10 resolve add with force adds', :'r4'='added');
select option_retire('expense_heads','transport','tmp') is not null as rt \gset
select option_other_log('expense_heads','merge into retired') ->> 'status' as l5 \gset
select tt.err('T10 merge into an inactive option refused', format($$select option_other_resolve(%L,'merge','transport')$$, (select id from list_other_entries where text='merge into retired')), 'option_inactive');
select option_reactivate('expense_heads','transport') is not null as ra \gset

\echo == T9 idempotent re-run of phase15
reset role;
select count(*) as nd, (select count(*) from option_requests) as nr, (select count(*) from list_other_entries) as nq, (select count(*) from option_lists) as nl from list_defs \gset
\i /home/user/My-tools/supabase/phase15.sql
select tt.chk('T9 re-run changes no data', (select count(*) from list_defs)=:nd and (select count(*) from option_requests)=:nr and (select count(*) from list_other_entries)=:nq and (select count(*) from option_lists)=:nl
  and (select add_rule from list_defs where list_code='wallets')='approval');
select tt.chk('T9 re-run keeps one guard trigger and rules', (select count(*) from pg_trigger where tgname='option_lists_guard')=1 and (select count(*) from rules where key in ('owner_self_approve','list_search_min'))=2);
insert into option_lists (list_code,value_code,label_bn,sort) values ('brand_new_list','a','এ',1);
select tt.chk('T9 a direct insert into a new list creates its list_defs row', exists (select 1 from list_defs where list_code='brand_new_list' and add_rule='approval'));
select tt.err('T9 delete requests blocked', 'delete from option_requests', 'nothing is deleted');
select tt.err('T9 delete other blocked', 'delete from list_other_entries', 'nothing is deleted');
select tt.err('T9 delete managers blocked', 'delete from list_managers', 'nothing is deleted');

select '--- FAILED: ' || count(*) filter (where not ok) || ' of ' || count(*) from tt.res;
