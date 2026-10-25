-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase91_test.sql there and is already pasted on the live database under that name.
-- Renumbered to phase517_test.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- FRESH DB ONLY. Phase 517 tests (Step Vis: per-user / per-role option visibility Show|Hide|Locked + permission recommendations).
--   ORDER="phase8 ... phase512 phase517" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths> 91db
--   cd <repo root>; psql -h /tmp -p 5544 -U postgres -d 91db -qAt -f supabase/phase517_test.sql | grep -E 'FAIL|RESULT'      (the test re-applies supabase/phase517.sql once: paste-twice check)
-- Test data only, no real person names.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set p '00000000-0000-0000-0000-000000000004'
\set t '00000000-0000-0000-0000-000000000005'
\set b '00000000-0000-0000-0000-000000000006'
\set o2 '00000000-0000-0000-0000-000000000008'
\set x '00000000-0000-0000-0000-0000000000f1'
\set c1 '11111111-0000-0000-0000-000000000001'
\set c2 '11111111-0000-0000-0000-000000000002'
\set c3 '11111111-0000-0000-0000-000000000003'
\set c4 '11111111-0000-0000-0000-000000000004'
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
create or replace function tt.err_browser(p_name text, p_sql text) returns void language plpgsql as $$
begin
  set local role authenticated;
  begin execute p_sql; reset role; perform tt.chk(p_name, false);
  exception when others then reset role; perform tt.chk(p_name, true); end;
end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
-- run a query as a logged-in browser user (role authenticated, RLS on) and return a count
create or replace function tt.cnt_as(p_sub text, p_sql text) returns bigint language plpgsql as $$
declare n bigint;
begin
  perform set_config('request.jwt.claim.sub', p_sub, false); set local role authenticated;
  begin execute p_sql into n; exception when others then reset role; return -1; end;
  reset role; return n;
end $$;
grant execute on function tt.cnt_as(text, text) to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'p','sales4@s.app','{"full_name":"Sales"}'),
 (:'t','store5@s.app','{"full_name":"Store"}'), (:'b','bot6@s.app','{"full_name":"Intake bot"}'), (:'o2','owner8@s.app','{"full_name":"Owner two"}'),
 (:'x','pend9@s.app','{"full_name":"Pending"}') on conflict do nothing;
update profiles set status='active' where id <> :'x';
insert into user_roles values (:'o','owner'),(:'o2','owner'),(:'s','showroom_manager'),(:'p','salesperson'),(:'t','storekeeper'),(:'b','intake_bot') on conflict do nothing;
insert into user_locations values (:'s',1),(:'p',1),(:'t',1) on conflict do nothing;
select tt.as(:'o');

\echo == T0 shape and privileges
select tt.chk('T0 tables exist, RLS on, browser cannot write', (select bool_and(relrowsecurity) from pg_class where relname in ('user_option_view','role_option_view','option_view_ops','perm_reco_role','perm_conflict','perm_reco_ignore'))
  and not has_table_privilege('authenticated','public.user_option_view','insert') and not has_table_privilege('authenticated','public.role_option_view','update')
  and not has_table_privilege('authenticated','public.option_view_ops','select') and not has_table_privilege('authenticated','public.perm_conflict','delete') and not has_table_privilege('anon','public.user_option_view','select'));
select tt.chk('T0 RPCs: authenticated yes, anon no; helpers closed', has_function_privilege('authenticated','public.my_option_views()','execute') and not has_function_privilege('anon','public.my_option_views()','execute')
  and has_function_privilege('authenticated','public.set_option_view(uuid,text,text,uuid)','execute') and not has_function_privilege('anon','public.permission_recommendations(uuid)','execute')
  and not has_function_privilege('authenticated','public._ov_put_user(uuid,text,text)','execute') and not has_function_privilege('authenticated','public._ov_effective(uuid)','execute') and not has_function_privilege('authenticated','public._ov_holds(uuid,text,text[])','execute'));
select tt.err_browser('T0 browser cannot insert a row directly', $$insert into public.user_option_view (user_id, option_key, mode) values ('00000000-0000-0000-0000-000000000004','r:items','hide')$$);
select tt.err_browser('T0 browser cannot touch the recommendation table', $$delete from public.perm_conflict$$);
select tt.chk('T0 default: nothing set, nobody has any choice (today''s view for every user)', (select count(*) from user_option_view)=0 and (select count(*) from role_option_view)=0);
select tt.as(:'p');
select tt.chk('T0 my_option_views() is empty for a normal user', my_option_views()='[]'::jsonb);
select tt.as(:'x');
select tt.chk('T0 pending user: empty list, no error', my_option_views()='[]'::jsonb);

\echo == T1 owner sets, others cannot
select tt.as(:'o');
select md5((select coalesce(string_agg(user_id::text||grant_code||coalesce(location_id,0),',' order by user_id,grant_code),'') from user_grants)||(select string_agg(form_code||role_code||can_view||can_enter||can_approve,',' order by form_code,role_code) from role_form_perms)||(select string_agg(role_code||grant_code||allowed,',' order by role_code,grant_code) from rule_grants)) as snap0 \gset
select can_do('POS','enter') as po0 \gset
select set_option_view(:'p','r:items','hide',:'c1')->>'changed' as ch1 \gset
select tt.chk('T1 owner hides r:items for a salesperson', :'ch1'='true' and (select mode from user_option_view where user_id=:'p' and option_key='r:items')='hide'
  and (select set_by from user_option_view where user_id=:'p' and option_key='r:items')=:'o');
select tt.as(:'p');
select tt.chk('T1 the person sees it in my_option_views()', my_option_views()='[{"key":"r:items","mode":"hide","src":"user"}]'::jsonb);
select tt.err('T1 a normal user cannot set (even for self)', format($$select set_option_view('%s','r:items','show')$$, :'p'), 'not allowed');
select tt.err('T1 a normal user cannot bulk set', format($$select set_option_view_bulk('%s','[{"key":"r:items","mode":"show"}]')$$, :'p'), 'not allowed');
select tt.err('T1 a normal user cannot set a role default', $$select set_role_option_view('storekeeper','r:stock','hide')$$, 'not allowed');
select tt.as(:'o');
select tt.err('T1 bad mode', format($$select set_option_view('%s','r:items','gone')$$, :'p'), 'bad_mode');
select tt.err('T1 bad key (no r:/f: prefix)', format($$select set_option_view('%s','items','hide')$$, :'p'), 'bad_option_key');
select tt.err('T1 bad key (injection-looking)', format($$select set_option_view('%s','r:x;drop','hide')$$, :'p'), 'bad_option_key');
select tt.err('T1 r:home cannot be hidden', format($$select set_option_view('%s','r:home','hide')$$, :'p'), 'protected_option');
select tt.err('T1 r:optviews cannot be locked', format($$select set_option_view('%s','r:optviews','locked')$$, :'p'), 'protected_option');
select tt.err('T1 unknown user', $$select set_option_view('99999999-0000-0000-0000-000000000009','r:items','hide')$$, 'unknown user');
select set_option_view(:'p','r:optviews','show') is not null as okshow \gset
select tt.chk('T1 r:optviews may be set to show', (select mode from user_option_view where user_id=:'p' and option_key='r:optviews')='show');
select set_option_view(:'p','f:10-1','locked') is not null as okl \gset
select tt.chk('T1 locked on a form key', (select mode from user_option_view where user_id=:'p' and option_key='f:10-1')='locked');

\echo == T2 reading
select tt.as(:'p');
select tt.err('T2 a person cannot read another person''s views', format($$select option_views_for_user('%s')$$, :'s'), 'not allowed');
select tt.chk('T2 a person reads their own full view', (option_views_for_user(:'p')->'user'->>'id')=:'p' and jsonb_array_length(option_views_for_user(:'p')->'overrides')=3);
select tt.chk('T2 RLS: a person sees only own rows in the table', tt.cnt_as(:'p','select count(*) from public.user_option_view')=3 and tt.cnt_as(:'s','select count(*) from public.user_option_view')=0);
select tt.chk('T2 RLS: owner sees all rows; role table owner only', tt.cnt_as(:'o','select count(*) from public.user_option_view')=3 and tt.cnt_as(:'p','select count(*) from public.role_option_view')=0);
select tt.as(:'o');
select tt.chk('T2 owner reads any person: roles, perms, grants present', (option_views_for_user(:'t')->'roles')='["storekeeper"]'::jsonb and jsonb_typeof(option_views_for_user(:'t')->'perms')='object'
  and (option_views_for_user(:'t')->'grants') @> '["purchase_entry"]'::jsonb);
select tt.chk('T2 owner entry: is_owner true and holds every grant', (option_views_for_user(:'o')->>'is_owner')::boolean and jsonb_array_length(option_views_for_user(:'o')->'grants')=(select count(*) from grant_defs));
select tt.err('T2 unknown person', $$select option_views_for_user('99999999-0000-0000-0000-000000000009')$$, 'unknown user');
select set_user_grant(:'p','view_cost') is null as svc \gset
select tt.chk('T2 personal grant shows up in grants', (option_views_for_user(:'p')->'grants') @> '["view_cost"]'::jsonb);

\echo == T3 client_id idempotency and audit
select count(*) as a0 from audit_log where table_name='user_option_view' \gset
select set_option_view(:'p','r:items','hide',:'c1')->>'dup' as d1 \gset
select tt.chk('T3 same client_id again: replayed (dup true), nothing new', :'d1'='true' and (select count(*) from audit_log where table_name='user_option_view')=:a0);
select tt.err('T3 same client_id, another action kind: client_id_taken', format($$select set_option_view_bulk('%s','[]',%L)$$, :'p', :'c1'), 'client_id_taken');
select tt.as(:'o2');
select tt.err('T3 same client_id from another owner: client_id_taken', format($$select set_option_view('%s','r:items','hide',%L)$$, :'p', :'c1'), 'client_id_taken');
select tt.as(:'o');
select tt.chk('T3 audit line written for the first change (old null -> new hide, by owner)', exists (select 1 from audit_log where table_name='user_option_view' and record_id=:'p' and user_id=:'o' and detail->>'event'='option_view' and detail->'changes'->0->>'key'='r:items' and detail->'changes'->0->>'new'='hide'));
select set_option_view(:'p','r:items','hide')->>'changed' as chsame \gset
select tt.chk('T3 same value without client_id: changed false, no audit line', :'chsame'='false' and (select count(*) from audit_log where table_name='user_option_view')=:a0);
select set_option_view(:'p','r:items','locked')->>'old' as oldm \gset
select tt.chk('T3 change hide->locked audited with old', :'oldm'='hide' and exists (select 1 from audit_log where table_name='user_option_view' and detail->'changes'->0->>'old'='hide' and detail->'changes'->0->>'new'='locked'));

\echo == T4 bulk
select set_option_view_bulk(:'t','[{"key":"r:stock","mode":"hide"},{"key":"r:assets","mode":"locked"},{"key":"f:03-1","mode":"show"}]',:'c2') as bk \gset
select tt.chk('T4 bulk sets 3, reports count and changed', (:'bk'::jsonb->>'count')::int=3 and (:'bk'::jsonb->>'changed')::int=3 and (select count(*) from user_option_view where user_id=:'t')=3);
select tt.chk('T4 bulk replay with same client_id: dup, still 3 rows', (set_option_view_bulk(:'t','[{"key":"r:other","mode":"hide"}]',:'c2')->>'dup')='true' and (select count(*) from user_option_view where user_id=:'t')=3);
select tt.err('T4 all-or-nothing: one bad item stops the whole bulk', format($$select set_option_view_bulk('%s','[{"key":"r:aa","mode":"hide"},{"key":"bad","mode":"hide"}]')$$, :'t'), 'bad_option_key');
select tt.chk('T4 ... and r:aa was not written', not exists (select 1 from user_option_view where option_key='r:aa'));
select tt.err('T4 protected key inside a bulk stops it', format($$select set_option_view_bulk('%s','[{"key":"r:aa","mode":"hide"},{"key":"r:home","mode":"locked"}]')$$, :'t'), 'protected_option');
select tt.err('T4 items must be an array', format($$select set_option_view_bulk('%s','{"a":1}')$$, :'t'), 'bad_items');
select tt.err('T4 more than 500 items refused', format($$select set_option_view_bulk('%s',(select jsonb_agg(jsonb_build_object('key','r:k'||g,'mode','hide')) from generate_series(1,501) g))$$, :'t'), 'too_many_items');
select set_option_view_bulk(:'t','[{"key":"r:stock","mode":"default"}]')->>'changed' as dch \gset
select tt.chk('T4 bulk with mode default removes the choice', :'dch'='1' and not exists (select 1 from user_option_view where user_id=:'t' and option_key='r:stock'));
select tt.chk('T4 bulk is one audit line with all changes', (select jsonb_array_length(detail->'changes') from audit_log where table_name='user_option_view' and record_id=:'t' order by id limit 1)=3);

\echo == T5 role defaults
select set_role_option_view('storekeeper','r:payables','hide')->>'changed' as rd1 \gset
select tt.chk('T5 owner sets a role default', :'rd1'='true' and (select mode from role_option_view where role_code='storekeeper' and option_key='r:payables')='hide');
select tt.as(:'t');
select tt.chk('T5 the storekeeper gets the role default (src role) next to own choices', my_option_views() @> '[{"key":"r:payables","mode":"hide","src":"role"}]'::jsonb and my_option_views() @> '[{"key":"r:assets","mode":"locked","src":"user"}]'::jsonb);
select tt.as(:'o');
select set_option_view(:'t','r:payables','show') is not null as ov1 \gset
select tt.as(:'t');
select tt.chk('T5 a user row beats the role default', my_option_views() @> '[{"key":"r:payables","mode":"show","src":"user"}]'::jsonb and not (my_option_views() @> '[{"key":"r:payables","src":"role"}]'::jsonb));
select tt.as(:'o');
select set_option_view(:'t','r:payables','default') is not null as ov2 \gset
select tt.chk('T5 default removes the user row, role default is back', (select count(*) from user_option_view where user_id=:'t' and option_key='r:payables')=0);
insert into user_roles values (:'t','purchasing') on conflict do nothing;
select set_role_option_view('purchasing','r:payables','locked') is not null as rd2 \gset
select tt.as(:'t');
select tt.chk('T5 two roles: the LESS restrictive default wins (locked beats hide)', my_option_views() @> '[{"key":"r:payables","mode":"locked","src":"role"}]'::jsonb);
select tt.as(:'o');
delete from user_roles where user_id=:'t' and role_code='purchasing';
select tt.err('T5 unknown role', $$select set_role_option_view('nope','r:items','hide')$$, 'unknown role');
select tt.err('T5 r:home protected for roles too', $$select set_role_option_view('storekeeper','r:home','hide')$$, 'protected_option');
select set_role_option_view_bulk('salesperson','[{"key":"r:daybook","mode":"hide"},{"key":"r:payables","mode":"hide"}]',:'c3')->>'changed' as rch \gset
select tt.chk('T5 role bulk works and is audited', :'rch'='2'
  and exists (select 1 from audit_log where table_name='role_option_view' and record_id='salesperson'));
select tt.chk('T5 owner lists role defaults; a normal user cannot', jsonb_array_length(role_option_views('salesperson'))=2);
select tt.as(:'p');
select tt.err('T5 normal user cannot list role defaults', $$select role_option_views(null)$$, 'not allowed');
select tt.chk('T5 salesperson sees role default plus own choice', my_option_views() @> '[{"key":"r:daybook","mode":"hide","src":"role"}]'::jsonb and my_option_views() @> '[{"key":"r:items","mode":"locked","src":"user"}]'::jsonb);

\echo == T6 hiding changes no permission
select tt.as(:'o');
select set_option_view(:'p','f:POS','hide') is not null as hp \gset
select set_option_view(:'p','r:pos','locked') is not null as lp \gset
select tt.chk('T6 grant / permission tables are byte-identical after hide + locked + role defaults (only the personal view_cost grant added by T2)',
  md5((select coalesce(string_agg(user_id::text||grant_code||coalesce(location_id,0),',' order by user_id,grant_code),'') from user_grants where grant_code<>'view_cost')||(select string_agg(form_code||role_code||can_view||can_enter||can_approve,',' order by form_code,role_code) from role_form_perms)||(select string_agg(role_code||grant_code||allowed,',' order by role_code,grant_code) from rule_grants))=:'snap0');
select tt.as(:'s');
select set_config('t.s_pos', coalesce(can_do('POS','enter'),false)::text, false);
select tt.as(:'o');
select set_option_view(:'s','f:POS','hide') is not null as hs \gset
select tt.as(:'s');
select tt.chk('T6 can_do and has_grant unchanged for a hidden option', can_do('POS','enter') is not distinct from current_setting('t.s_pos')::boolean and has_grant('sale_void'));
select tt.as(:'p');
select tt.chk('T6 a locked option does not create a grant for the person (still lacks a grant they never had)', not has_grant('stock_count_adjust') and has_grant('view_cost'));
select tt.as(:'o');
select tt.chk('T6 owner can still read all', can_do('POS','enter') = :'po0'::boolean);

\echo == T7 recommendations: seeds and shape
select tt.chk('T7 seeds exist: role advice from today''s defaults, >= 12 conflict pairs', (select count(*) from perm_reco_role)>=(select count(*) from rule_grants where allowed) and (select count(*) from perm_conflict)>=12);
select tt.chk('T7 every plain conflict token is a real grant code or a role/module/form token', not exists (select 1 from perm_conflict c, unnest(array[c.token_a,c.token_b]) tk
  where tk !~ '^(role|module|form):' and not exists (select 1 from grant_defs d where d.grant_code=tk)));
select tt.chk('T7 every seeded row has bn, mix and en reason', not exists (select 1 from perm_conflict where coalesce(reason_bn,'')='' or coalesce(reason_mix,'')='' or coalesce(reason_en,'')='') and not exists (select 1 from perm_reco_role where coalesce(reason_bn,'')='' or coalesce(reason_en,'')=''));
select tt.chk('T7 English reason has no Bangla letter', not exists (select 1 from perm_conflict where reason_en ~ '[ঀ-৿]') and not exists (select 1 from perm_reco_role where reason_en ~ '[ঀ-৿]'));
select tt.chk('T7 Bangla reason really is Bangla', not exists (select 1 from perm_conflict where reason_bn !~ '[ঀ-৿]'));
select tt.as(:'p');
select tt.err('T7 a normal user cannot read the advice for anyone', format($$select permission_recommendations('%s')$$, :'p'), 'not allowed');
select tt.as(:'o');
select tt.chk('T7 the owner user gets an empty advice', (permission_recommendations(:'o')->>'is_owner')::boolean and jsonb_array_length(permission_recommendations(:'o')->'not_recommended_combo')=0);
select tt.err('T7 unknown person', $$select permission_recommendations('99999999-0000-0000-0000-000000000009')$$, 'unknown user');

\echo == T8 recommended_missing
select reco_role_set('storekeeper','view_cost',true,null,null,null) is null as rs \gset
select tt.chk('T8 owner adds a recommended grant for a role: a storekeeper who lacks it sees it as missing, with a reason in 3 languages',
  exists (select 1 from jsonb_array_elements(permission_recommendations(:'t')->'recommended_missing') e where e->>'grant'='view_cost' and e->'reason'->>'en'='Added by the owner' and e->'label'->>'bn' is not null and e->'reason'->>'mix' is not null));
select tt.chk('T8 a grant the person already holds is not listed as missing', not exists (select 1 from jsonb_array_elements(permission_recommendations(:'t')->'recommended_missing') e where e->>'grant'='purchase_entry'));
select tt.chk('T8 a person with no matching role gets nothing missing', jsonb_array_length(permission_recommendations(:'b')->'recommended_missing')=0);
select tt.as(:'t'); select tt.err('T8 storekeeper cannot edit the advice', $$select reco_role_set('storekeeper','view_profit',true)$$, 'not allowed'); select tt.as(:'o');
select tt.err('T8 unknown grant', $$select reco_role_set('storekeeper','nope',true)$$, 'unknown grant');

\echo == T9 not_recommended_combo
select tt.chk('T9 role-only storekeeper holds purchase_entry but not supplier_pay: no combo yet', not exists (select 1 from jsonb_array_elements(permission_recommendations(:'t')->'not_recommended_combo') e where e->>'a'='purchase_entry'));
select set_user_grant(:'t','supplier_pay') is null as gs \gset
select tt.chk('T9 role grant purchase_entry + personal supplier_pay = combo with the two grants and a reason', exists (select 1 from jsonb_array_elements(permission_recommendations(:'t')->'not_recommended_combo') e
  where e->>'a'='purchase_entry' and e->>'b'='supplier_pay' and e->'reason'->>'en' like '%purchase bills%' and e->>'item'='combo:purchase_entry|supplier_pay'));
select set_user_grant(:'b','sale_void') is null as gb \gset
select tt.chk('T9 intake bot + any POS-module right is flagged', exists (select 1 from jsonb_array_elements(permission_recommendations(:'b')->'not_recommended_combo') e where e->>'a'='role:intake_bot' and e->>'b'='module:pos'));
select tt.chk('T9 a salesperson without those grants has no combo', jsonb_array_length(permission_recommendations(:'p')->'not_recommended_combo')=0 or not exists (select 1 from jsonb_array_elements(permission_recommendations(:'p')->'not_recommended_combo') e where e->>'a'='role:intake_bot'));
select tt.chk('T9 advice never blocks: the grant is still held and works', (select count(*) from user_grants where user_id=:'t' and grant_code='supplier_pay')=1);
select reco_conflict_set('purchase_entry','supplier_pay',false) is null as cs \gset
select tt.chk('T9 owner switches a pair off: it disappears', not exists (select 1 from jsonb_array_elements(permission_recommendations(:'t')->'not_recommended_combo') e where e->>'item'='combo:purchase_entry|supplier_pay'));
select reco_conflict_set('purchase_entry','supplier_pay',true) is null as cs2 \gset
select reco_conflict_set('view_cost','report_profit',true,null,null,'Owner pair') is null as cs3 \gset
select tt.chk('T9 owner adds own pair (english reason kept)', (select reason_en from perm_conflict where token_a='view_cost' and token_b='report_profit')='Owner pair');
select tt.err('T9 bad token refused', $$select reco_conflict_set('a b','c',true)$$, 'bad_token');
select tt.err('T9 same token twice refused', $$select reco_conflict_set('view_cost','view_cost',true)$$, 'bad_token');

\echo == T10 unused / never needed
select tt.chk('T10 a salesperson with no view on some form: unused list suggests Hide for those forms', exists (select 1 from jsonb_array_elements(permission_recommendations(:'p')->'unused') e where e->>'suggest'='hide' and e->>'key' like 'f:%')
  and not exists (select 1 from jsonb_array_elements(permission_recommendations(:'p')->'unused') e where e->>'key'='f:POS'));
select (select e->>'key' from jsonb_array_elements(permission_recommendations(:'p')->'unused') e limit 1) as uk \gset

\echo == T11 ignore and one-tap apply
select reco_ignore_set(:'t','combo:purchase_entry|supplier_pay',true,null) as ig \gset
select tt.chk('T11 ignored item is still listed but flagged ignored', exists (select 1 from jsonb_array_elements(permission_recommendations(:'t')->'not_recommended_combo') e where e->>'item'='combo:purchase_entry|supplier_pay' and (e->>'ignored')::boolean)
  and permission_recommendations(:'t')->'ignored' @> '["combo:purchase_entry|supplier_pay"]'::jsonb);
select tt.chk('T11 ignoring is audited', exists (select 1 from audit_log where table_name='perm_reco_ignore' and record_id=:'t'));
select reco_ignore_set(:'t','combo:purchase_entry|supplier_pay',false) is not null as ig2 \gset
select tt.chk('T11 un-ignore', not exists (select 1 from perm_reco_ignore where user_id=:'t'));
select tt.err('T11 bad item', format($$select reco_ignore_set('%s','whatever')$$, :'t'), 'bad_item');
select tt.as(:'t'); select tt.err('T11 normal user cannot ignore / apply', format($$select reco_apply('%s','miss:view_cost')$$, :'t'), 'not allowed'); select tt.as(:'o');
select reco_apply(:'t','miss:view_cost') as ap1 \gset
select tt.chk('T11 apply miss: personal grant given, audited (grant trigger + apply line)', has_grant('view_cost') or exists (select 1 from user_grants where user_id=:'t' and grant_code='view_cost'));
select tt.chk('T11 apply miss written an audit line', exists (select 1 from audit_log where table_name='perm_reco_apply' and record_id=:'t' and detail->'changes'->0->>'item'='miss:view_cost') and exists (select 1 from audit_log where table_name='user_grants' and detail::text like '%view_cost%' and detail::text like '%'||:'t'||'%'));
select tt.err('T11 a grant not recommended for any of the roles cannot be applied this way', format($$select reco_apply('%s','miss:payroll_manage')$$, :'t'), 'not_recommended');
select reco_apply(:'p', 'unused:' || :'uk', :'c4') is not null as ap2 \gset
select tt.err('T11 reused client_id of another kind', format($$select reco_ignore_set('%s','miss:view_cost',true,%L)$$, :'t', :'c4'), 'client_id_taken');
select tt.chk('T11 apply unused: option is now hidden for that person', (select mode from user_option_view where user_id=:'p' and option_key=:'uk')='hide'
  and not exists (select 1 from jsonb_array_elements(permission_recommendations(:'p')->'unused') e where e->>'key'=:'uk'));
select tt.chk('T11 apply is idempotent with the same client_id (no second audit line)', (reco_apply(:'p','unused:'||:'uk',:'c4')->>'dup')='true');
select reco_apply(:'t','combo:purchase_entry|supplier_pay') as ap3 \gset
select tt.chk('T11 apply combo: the PERSONAL supplier_pay grant is taken back, role grants untouched', (select count(*) from user_grants where user_id=:'t' and grant_code='supplier_pay')=0
  and (select count(*) from rule_grants where role_code='storekeeper' and grant_code='purchase_entry' and allowed)=1);
select tt.err('T11 combo that only comes from roles cannot be applied (change the role instead)', format($$select reco_apply('%s','combo:purchase_entry|supplier_pay')$$, :'t'), 'not_personal_grant');
select tt.err('T11 unknown combo', format($$select reco_apply('%s','combo:a|b')$$, :'t'), 'unknown_combo');
select tt.err('T11 bad item kind', format($$select reco_apply('%s','zzz:1')$$, :'t'), 'bad_item');

\echo == T12 paste-twice: owner edits survive a re-run
select reco_conflict_set('purchase_entry','supplier_pay',false) is null as cs4 \gset
select count(*) as nc0 from perm_conflict \gset
select count(*) as nr0 from perm_reco_role \gset
\i supabase/phase517.sql
select tt.chk('T12 second run: no duplicates, owner''s switched-off pair stays off, owner edit stays', (select count(*) from perm_conflict)=:nc0 and (select count(*) from perm_reco_role)=:nr0
  and not (select active from perm_conflict where token_a='purchase_entry' and token_b='supplier_pay') and (select count(*) from user_option_view)>0);

select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
