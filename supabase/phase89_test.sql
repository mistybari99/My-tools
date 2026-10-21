-- FRESH DB ONLY. Phase 89 tests (U-02 period integrity: pure-date lock, owner override with reason, back-date window, late offline sale policy, guards on rules).
--   a database built through phase 87, then phase 89 pasted ONCE:
--   ORDER="phase8 ... phase87 phase89" bash tests/sql/build_fresh_db.sh a89db        (port 5562 here)
--   psql -h /tmp -p 5562 -U postgres -d a89db -qAt -f supabase/phase89_test.sql | grep -E 'FAIL|RESULT'
-- PART A runs BEFORE the hooks: the shared functions are untouched and everything behaves as today. PART B installs the hooks of docs/integration/W1-B_hooks.sql
-- on this throwaway database (the "scratch copy": the committed phase89.sql never patches a shared function) and proves defaults = old behaviour and the new behaviour.
-- Test data only (test_* names). The test database is changed by the hooks at the end: run it on a fresh build only.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000000089'
\set u_acc '00000000-0000-0000-0000-000000000189'
\set u_st '00000000-0000-0000-0000-000000000289'
\set u_m1 '00000000-0000-0000-0000-000000000389'
\set u_st2 '00000000-0000-0000-0000-000000000489'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.ok(p_name text, p_sql text) returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, true);
exception when others then perform tt.chk(p_name, false); raise notice '  (got: %)', sqlerrm; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.unbalanced() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
create or replace function tt.exn(p_kind text) returns bigint language sql stable as $$ select count(*) from public.money_exceptions where kind = p_kind $$;
create or replace function tt.aln(p_action text) returns bigint language sql stable as $$ select count(*) from public.audit_log where action = p_action $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner@s.app','{"full_name":"test_owner"}'), (:'u_acc','test_acct@s.app','{"full_name":"test_acct"}'), (:'u_st','test_cashier@s.app','{"full_name":"test_cashier"}'),
 (:'u_m1','test_mgr1@s.app','{"full_name":"test_mgr1"}'), (:'u_st2','test_cashier2@s.app','{"full_name":"test_cashier2"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_o','owner'),(:'u_acc','management'),(:'u_st','salesperson'),(:'u_m1','showroom_manager'),(:'u_st2','salesperson') on conflict do nothing;
insert into user_locations values (:'u_acc',1),(:'u_acc',2),(:'u_st',1),(:'u_m1',1),(:'u_st2',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_acc','accounts_manage',null),(:'u_acc','accounts_view',null),(:'u_acc','cash_move',1),(:'u_m1','cash_move',1);
insert into suppliers (name) values ('test_supplier_89');
select id as sup from suppliers where name='test_supplier_89' \gset
select (tt.today() - 40) as ld \gset
select (tt.today() - 45) as dc \gset
select (tt.today() - 10) as d10 \gset
select (tt.today() - 3) as d3 \gset
select (tt.today() - 5) as d5 \gset
select (tt.today() - 400) as d400 \gset
select (tt.today() - 20) as d20 \gset
select (tt.today() - 60) as d60 \gset

\echo == A0 shape, safe defaults, internals closed (shared functions NOT patched yet)
select tt.chk('A0 phase89 present, paste twice leaves the rules and grants once',
  to_regprocedure('public._p89_present()') is not null and (select count(*) from rules where key in ('period_lock_mode','auto_lock_day','owner_closed_period_mode','period_override_default_minutes','lock_backward_policy',
   'backdate_max_days_purchase','backdate_max_days_cash_move','backdate_max_days_expense','backdate_max_days_production','late_sale_policy','start_date_lock_after_opening','accounting_on_needs_reason'))=12
  and (select count(*) from grant_defs where grant_code in ('late_sale_release','backdate_over_limit'))=2);
select tt.chk('A0 every default keeps today: manual lock, owner silent, no auto day, no back-date limit, redate, guards off, 60 minute windows, backward allowed',
  rule_txt('period_lock_mode')='manual' and rule_txt('owner_closed_period_mode')='off' and rule_num('auto_lock_day') is null and rule_num('backdate_max_days_purchase') is null
  and rule_num('backdate_max_days_cash_move') is null and rule_num('backdate_max_days_expense') is null and rule_num('backdate_max_days_production') is null and rule_txt('late_sale_policy')='redate'
  and not rule_on('start_date_lock_after_opening') and not rule_on('accounting_on_needs_reason') and rule_num('period_override_default_minutes')=60 and rule_txt('lock_backward_policy')='allow');
select tt.chk('A0 labels are English and each setting has a hint', (select count(*) from rules where key in ('period_lock_mode','auto_lock_day','owner_closed_period_mode','period_override_default_minutes','lock_backward_policy',
   'backdate_max_days_purchase','backdate_max_days_cash_move','backdate_max_days_expense','backdate_max_days_production','late_sale_policy','start_date_lock_after_opening','accounting_on_needs_reason')
   and label_en ~ '^[A-Za-z]' and label_bn = label_en and hint_en is not null)=12);
select tt.chk('A0 the Exceptions list knows the new kinds and kept the old ones', (select pg_get_constraintdef(oid) from pg_constraint where conname='money_exceptions_kind_check') ~ 'late_sale_held'
  and (select pg_get_constraintdef(oid) from pg_constraint where conname='money_exceptions_kind_check') ~ 'backdate_exception' and (select pg_get_constraintdef(oid) from pg_constraint where conname='money_exceptions_kind_check') ~ 'period_lock_exception'
  and (select pg_get_constraintdef(oid) from pg_constraint where conname='money_exceptions_kind_check') ~ 'recon_diff');
select tt.chk('A0 internals closed to browsers, owner screens open to the API only',
  not has_function_privilege('authenticated','public._w1b_lock_allowed(date)','execute') and not has_function_privilege('authenticated','public._w1b_backdate_check(text,date,uuid,text)','execute')
  and not has_function_privilege('authenticated','public._w1b_patch(regprocedure,text,text[])','execute') and not has_function_privilege('authenticated','public._w1b_override_take(text,date,text)','execute')
  and not has_function_privilege('authenticated','public._w1b_late_sale(uuid,int,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric,timestamptz)','execute')
  and has_function_privilege('authenticated','public.period_override_start(text,date,date,int,text,uuid,text)','execute') and not has_function_privilege('anon','public.period_lock_state()','execute')
  and not has_function_privilege('anon','public.late_sale_release(bigint,text,text)','execute'));
select tt.chk('A0 the tables cannot be written by a browser role and have no delete', not has_table_privilege('authenticated','public.period_overrides','insert') and not has_table_privilege('authenticated','public.late_sales_held','update')
  and not has_table_privilege('anon','public.period_overrides','select'));
select tt.chk('A0 both tables are protected against delete by the no_hard_delete trigger (tested with rows below)', exists (select 1 from pg_trigger where tgname='period_overrides_nodel') and exists (select 1 from pg_trigger where tgname='late_sales_held_nodel'));
select tt.chk('A0 the shared functions are NOT patched by phase89 itself (marker bos89 absent)',
  (select count(*) from (values ('public.lock_check(date)'),('public._acct_locked(date)'),('public.record_sale2(uuid,int,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)'),
    ('public.cash_move_add(int,text,numeric,date,text,uuid,text,text,uuid,boolean)'),('public.quick_expense_add(int,date,text,text,numeric,text,boolean,text,uuid)'),
    ('public.save_purchase(uuid,uuid,uuid,int,text,date,jsonb,numeric,text,text,text,uuid,text)'),('public.production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)')) v(f)
   where position('bos89' in pg_get_functiondef(v.f::regprocedure))>0)=0);
select tt.as(:'u_o');
select tt.chk('A0 the state function reports the hooks as not installed', (select bool_and(not v::boolean) from jsonb_each_text(period_lock_state() -> 'hooks') h(k, v)) is true);

\echo == A1 the automatic month lock arithmetic (fixed dates, pure function)
select tt.chk('A1 day 10: on the 16th the previous month is closed', _w1b_auto_date(date '2026-10-16', 10) = date '2026-09-30');
select tt.chk('A1 day 10: on the 10th itself the month before that is the last closed one', _w1b_auto_date(date '2026-10-10', 10) = date '2026-08-31');
select tt.chk('A1 day 10: on the 11th the previous month closes', _w1b_auto_date(date '2026-10-11', 10) = date '2026-09-30');
select tt.chk('A1 year turn: 5 January, day 10, closes through 30 November', _w1b_auto_date(date '2026-01-05', 10) = date '2025-11-30');
select tt.chk('A1 day 28 on 28 March: the month before the previous (leap-free February end of the month before)', _w1b_auto_date(date '2026-03-28', 28) = date '2026-01-31');
select tt.chk('A1 day 28 on 29 March: February is closed', _w1b_auto_date(date '2026-03-29', 28) = date '2026-02-28');
select tt.chk('A1 a blank or impossible day locks nothing', _w1b_auto_date(date '2026-10-16', null) is null and _w1b_auto_date(date '2026-10-16', 0) is null and _w1b_auto_date(date '2026-10-16', 31) is null);
select tt.chk('A1 an impossible typed date locks nobody out', _w1b_pdate('2026-02-30') is null and _w1b_pdate('x') is null and _w1b_pdate('2026-09-30') = date '2026-09-30');

\echo == A2 the effective lock date by mode (pure, the same for everyone)
reset role;
update rules set value = to_jsonb(:'ld'::text) where key = 'period_closed_until';
select tt.chk('A2 manual (default): the typed date', _w1b_lock_date() = :'ld'::date and _w1b_is_locked(:'dc'::date) and not _w1b_is_locked(tt.today()));
update rules set value = '"off"' where key = 'period_lock_mode';
select tt.chk('A2 off: no lock at all, whatever is typed', _w1b_lock_date() is null and not _w1b_is_locked(:'dc'::date));
update rules set value = '"auto"' where key = 'period_lock_mode';
select tt.chk('A2 auto with no day set locks nothing by itself: the typed date still counts', _w1b_lock_date() = :'ld'::date);
update rules set value = '10' where key = 'auto_lock_day';
select tt.chk('A2 auto day 10: the later of the typed date and the automatic date', _w1b_lock_date() = greatest(:'ld'::date, _w1b_auto_date(tt.today(), 10)));
update rules set value = null where key = 'auto_lock_day';
update rules set value = null where key = 'period_lock_mode';
select tt.chk('A2 back to the default mode: the typed date again', _w1b_lock_date() = :'ld'::date);

\echo == A3 BEFORE the hooks: lock_check is the old function, the owner is silent whatever the new settings say
update rules set value = '"reason"' where key = 'owner_closed_period_mode';
set role authenticated; select tt.as(:'u_o');
select tt.ok('A3 owner dates a cash move into the closed month (old lock_check, no hook)', format($$select cash_move_add(1,'owner_topup',11,%L::date,'cash',null,'t_a3',null,gen_random_uuid(),false)$$, :'dc'));
reset role; select tt.as(:'u_acc');
select tt.err('A3 the accountant is refused in the closed month (old rule)', format($$select public.lock_check(%L::date)$$, :'dc'), 'period_closed');
update rules set value = null where key = 'owner_closed_period_mode';
select tt.chk('A3 nothing was written to the Exceptions list or the audit trail by the missing hook', tt.exn('period_lock_exception')=0 and tt.aln('period_owner_closed_date')=0);

\echo == A4 policy setter, windows and lists work without the hooks
set role authenticated; select tt.as(:'u_o');
select tt.err('A4 unknown setting refused', $$select period_lock_policy_set('accounting_on', 'true'::jsonb, 'x')$$, 'unknown_setting');
select tt.err('A4 out of range number refused (day 40)', $$select period_lock_policy_set('auto_lock_day', '40'::jsonb, 'x')$$, 'bad_value');
select tt.err('A4 text where a choice is needed refused', $$select period_lock_policy_set('late_sale_policy', '"sometimes"'::jsonb, 'x')$$, 'bad_value');
select tt.err('A4 auto mode with no day is refused (a blank number blocks)', $$select period_lock_policy_set('period_lock_mode', '"auto"'::jsonb, 'x')$$, 'auto_lock_day_missing');
select period_lock_policy_set('auto_lock_day', '10'::jsonb, 'test day') is not null as ad1 \gset
select tt.chk('A4 the change is in audit_log twice: the rule line and the note line', exists (select 1 from audit_log where action='period_policy_set' and record_id='auto_lock_day' and detail ->> 'note'='test day')
  and exists (select 1 from audit_log where table_name='rules' and record_id='auto_lock_day' and action='update'));
select period_lock_policy_set('period_lock_mode', '"auto"'::jsonb, 'test auto') is not null as am1 \gset
select tt.err('A4 clearing the day while the mode is auto is refused (guard)', $$select set_rule('auto_lock_day', null)$$, 'auto_lock_day_missing');
select period_lock_policy_set('period_lock_mode', '"manual"'::jsonb, 'back') is not null as am2 \gset
select period_lock_policy_set('auto_lock_day', null, 'cleared') is not null as ad2 \gset
select tt.chk('A4 blank again', rule_num('auto_lock_day') is null and rule_txt('period_lock_mode')='manual');
select tt.as(:'u_acc');
select tt.err('A4 the accountant cannot change a policy', $$select period_lock_policy_set('late_sale_policy', '"park"'::jsonb, 'x')$$, 'not allowed');
select tt.err('A4 the accountant cannot open a window', format($$select period_override_start('test reason', %L::date, %L::date, 30)$$, :'dc', :'dc'), 'not allowed');
select tt.err('A4 the accountant cannot read the log', $$select period_override_log()$$, 'not allowed');
select tt.err('A4 the accountant cannot read the lateness report', $$select period_lateness_report(30)$$, 'not allowed');
select tt.err('A4 the accountant cannot set the lock date', format($$select period_lock_set(%L::date, 'x')$$, :'ld'), 'not allowed');
select tt.err('A4 the accountant cannot see held sales', $$select late_sales_held_list()$$, 'not allowed');
select tt.chk('A4 the accountant can read the state but sees no one else''s windows', (period_lock_state() ->> 'owner')::boolean is false and jsonb_array_length(period_lock_state() -> 'open_windows')=0);
select tt.as(:'u_st');
select tt.err('A4 a salesperson cannot open a window', format($$select period_override_start('test reason', %L::date, %L::date, 30)$$, :'dc', :'dc'), 'not allowed');
select tt.err('A4 a salesperson cannot release a held sale', $$select late_sale_release(1, 'accept', 'test reason')$$, 'not allowed');
reset role;

\echo == A5 window rules (without the hooks): reason, dates, minutes, scope, person
set role authenticated; select tt.as(:'u_o');
select tt.err('A5 a window needs a reason', format($$select period_override_start('', %L::date, %L::date, 30)$$, :'dc', :'dc'), 'reason_required');
select tt.err('A5 a window needs a reason of 3 characters', format($$select period_override_start('ab', %L::date, %L::date, 30)$$, :'dc', :'dc'), 'reason_required');
select tt.err('A5 from after to refused', format($$select period_override_start('test reason', %L::date, %L::date, 30)$$, :'ld', :'dc'), 'bad_date');
select tt.err('A5 a year 1999 date refused', $$select period_override_start('test reason', date '1999-01-01', date '1999-02-01', 30)$$, 'bad_date');
select tt.err('A5 minutes 0 refused', format($$select period_override_start('test reason', %L::date, %L::date, 0)$$, :'dc', :'dc'), 'bad_minutes');
select tt.err('A5 minutes 2000 refused', format($$select period_override_start('test reason', %L::date, %L::date, 2000)$$, :'dc', :'dc'), 'bad_minutes');
select tt.err('A5 bad scope refused', format($$select period_override_start('test reason', %L::date, %L::date, 30, 'everything')$$, :'dc', :'dc'), 'bad_scope');
select tt.err('A5 bad document type refused', format($$select period_override_start('test reason', %L::date, %L::date, 30, 'both', null, 'sale')$$, :'dc', :'dc'), 'bad_doc');
select tt.err('A5 an unknown person refused', format($$select period_override_start('test reason', %L::date, %L::date, 30, 'lock', gen_random_uuid())$$, :'dc', :'dc'), 'unknown_user');
select (period_override_start('test reason one', :'dc'::date - 5, :'dc'::date + 5) ->> 'id')::bigint as w0 \gset
select tt.chk('A5 default length comes from the setting (60 minutes)', (select expires_at - started_at from period_overrides where id=:'w0') between interval '59 minutes' and interval '61 minutes');
select tt.chk('A5 the start is an audit_log line with the reason', exists (select 1 from audit_log where action='period_override_start' and record_id=:'w0' and detail ->> 'reason'='test reason one'));
select period_override_end(:'w0'::bigint, 'test done') is not null as we0 \gset
select tt.err('A5 ending twice refused', format($$select period_override_end(%s)$$, :'w0'), 'not found');
select tt.chk('A5 an ended window stays in the log (never deleted)', (select ended_at is not null from period_overrides where id=:'w0') and jsonb_array_length(period_override_log() -> 'windows')>=1);
reset role;

\echo == B0 install the hooks on this scratch database (docs/integration/W1-B_hooks.sql), twice
select tt.as(:'u_o');
\ir ../docs/integration/W1-B_hooks.sql
\ir ../docs/integration/W1-B_hooks.sql
select tt.chk('B0 all seven functions carry the marker bos89, each once', (select count(*) from (values ('public.lock_check(date)'),('public._acct_locked(date)'),('public.record_sale2(uuid,int,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)'),
    ('public.cash_move_add(int,text,numeric,date,text,uuid,text,text,uuid,boolean)'),('public.quick_expense_add(int,date,text,text,numeric,text,boolean,text,uuid)'),
    ('public.save_purchase(uuid,uuid,uuid,int,text,date,jsonb,numeric,text,text,text,uuid,text)'),('public.production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)')) v(f)
   where position('bos89' in pg_get_functiondef(v.f::regprocedure))>0 and (length(pg_get_functiondef(v.f::regprocedure)) - length(replace(pg_get_functiondef(v.f::regprocedure), 'bos89', '')))/5 between 1 and 4)=7);
select tt.chk('B0 the earlier tags survive (bos87 in lock_check, bos43 / bos22-late in record_sale2, bos50 chain intact)', position('bos87' in pg_get_functiondef('public.lock_check(date)'::regprocedure))>0
  and position('bos43' in pg_get_functiondef('public.record_sale2(uuid,int,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)'::regprocedure))>0
  and position('bos22-late' in pg_get_functiondef('public.record_sale2(uuid,int,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)'::regprocedure))>0);
select tt.chk('B0 paste twice: a second run of the helper patches nothing', not _w1b_patch('public.lock_check(date)'::regprocedure, 'bos89', array['x', 'y bos89']));
select tt.err('B0 a missing patch site stops the patch with a message and changes nothing', $$select _w1b_patch('public.lock_check(date)'::regprocedure, 'bos90', array['this text is not there', 'x bos90'])$$, 'patch site not found');
select tt.chk('B0 the state function reports all hooks installed', (select bool_and(v::boolean) from jsonb_each_text(period_lock_state() -> 'hooks') h(k, v)) is true);
\ir phase89.sql
select tt.chk('B0 phase89 pasted a second time after the hooks: hooks still in place and 12 rules once', position('bos89' in pg_get_functiondef('public.lock_check(date)'::regprocedure))>0
  and (select count(*) from rules where key in ('period_lock_mode','auto_lock_day','owner_closed_period_mode','period_override_default_minutes','lock_backward_policy','backdate_max_days_purchase','backdate_max_days_cash_move',
   'backdate_max_days_expense','backdate_max_days_production','late_sale_policy','start_date_lock_after_opening','accounting_on_needs_reason'))=12);

\echo == B1 DEFAULTS WITH THE HOOKS = TODAY. Typed lock date is set; owner silent, accountant refused, sale re-dated, nothing back-dated is refused
select (tt.today() - 40) as ld \gset
set role authenticated; select tt.as(:'u_o');
select tt.ok('B1 owner dates a cash move into the closed month: silent, as today', format($$select cash_move_add(1,'owner_topup',12,%L::date,'cash',null,'t_b1',null,gen_random_uuid(),false)$$, :'dc'));
select tt.ok('B1 owner dates a cash move to the year 2000: allowed, as today', $$select cash_move_add(1,'owner_topup',13,date '2000-01-02','cash',null,'t_b1b',null,gen_random_uuid(),false)$$);
select tt.ok('B1 owner back-dates a purchase bill 400 days: allowed, as today', format($$select save_purchase(gen_random_uuid(),null,%L::uuid,1,'B1-1',%L::date,'[{"description":"x","qty":1,"unit_cost":5}]'::jsonb)$$, :'sup', :'d400'));
select tt.as(:'u_acc');
select tt.err('B1 accountant dates a cash move into the closed month: refused, as today', format($$select cash_move_add(1,'owner_topup',14,%L::date,'cash',null,'t_b1c',null,gen_random_uuid(),false)$$, :'dc'), 'period_closed');
select tt.ok('B1 accountant outside the closed month is fine', format($$select cash_move_add(1,'owner_topup',15,%L::date,'cash',null,'t_b1d',null,gen_random_uuid(),false)$$, :'d10'));
reset role;
select tt.chk('B1 no new exception line and no new audit action from any of this', tt.exn('period_lock_exception')=0 and tt.exn('backdate_exception')=0 and tt.exn('late_sale_held')=0 and tt.exn('late_sale_redated')=0
  and tt.aln('period_owner_closed_date')=0 and tt.aln('period_override_used')=0);
select tt.as(:'u_o');
select tt.chk('B1 _acct_locked is the old function for the owner (false)', (select not _acct_locked(:'dc'::date)) and not _w1b_pure_posting());
select tt.as(:'u_acc');
select tt.chk('B1 _acct_locked for the accountant stays user dependent while the owner mode is off', _acct_locked(:'dc'::date));
select tt.as(:'u_o');

\echo == B2 the late offline sale with the DEFAULT policy (redate): the sale takes the server time, no exception
set role authenticated; select tt.as(:'u_st');
select record_sale2(gen_random_uuid(),1,'[{"amount":700}]',0,'[{"mode":"cash","amount":700}]',null,null,'retail',null,true, now() - interval '80 hours') ->> 'id' as s80 \gset
select tt.chk('B2 an 80 hour old sale is re-dated to now (as today)', (select abs(extract(epoch from now() - sold_at)) < 30 from sales where id=:'s80'::uuid) and (select sale_date from sales where id=:'s80'::uuid)=tt.today());
reset role;
select tt.chk('B2 and writes nothing to the Exceptions list in the default policy', tt.exn('late_sale_held')=0 and tt.exn('late_sale_redated')=0 and (select count(*) from late_sales_held)=0);
set role authenticated; select tt.as(:'u_st');
select record_sale2(gen_random_uuid(),1,'[{"amount":710}]',0,'[{"mode":"cash","amount":710}]',null,null,'retail',null,true, now() - interval '60 hours') ->> 'id' as s60 \gset
select tt.chk('B2 a 60 hour old sale keeps its own time (inside the 72 hour limit)', (select abs(extract(epoch from (now() - interval '60 hours') - sold_at)) < 30 from sales where id=:'s60'::uuid));
select record_sale2(gen_random_uuid(),1,'[{"amount":720}]',0,'[{"mode":"cash","amount":720}]',null,null,'retail',null,true, now() + interval '3 hours') ->> 'id' as sfut \gset
select tt.chk('B2 a time in the future is corrected to now, as before', (select sold_at <= now() + interval '1 minute' from sales where id=:'sfut'::uuid));

\echo == B3 the typed lock date with the owner mode LOG: the owner may, and every use is logged
set role authenticated; select tt.as(:'u_o');
select period_lock_policy_set('owner_closed_period_mode', '"log"'::jsonb, 'test log') is not null as lg1 \gset
select tt.ok('B3 owner dates a cash move into the closed month (log mode)', format($$select cash_move_add(1,'owner_topup',21,%L::date,'cash',null,'t_b3',null,gen_random_uuid(),false)$$, :'dc'));
reset role;
select tt.chk('B3 one Exceptions line and one audit line for that transaction', tt.exn('period_lock_exception')=1 and tt.aln('period_owner_closed_date')=1);
select tt.chk('B3 the Exceptions line carries the date', (select reason from money_exceptions where kind='period_lock_exception' order by id desc limit 1) like '%closed date%' || :'dc' || '%');
select tt.chk('B3 now _acct_locked is a pure date test: the same answer for the owner and the accountant', (select _acct_locked(:'dc'::date)) and not _acct_locked(tt.today()) and _w1b_pure_posting());
select tt.as(:'u_acc');
select tt.chk('B3 the accountant gets the same answer', _acct_locked(:'dc'::date) and not _acct_locked(tt.today()));
select tt.as(:'u_o');

\echo == B4 the owner mode REASON: refused without a window, allowed with one (reason, dates, minutes), one audit line and one red line per use
set role authenticated; select tt.as(:'u_o');
select period_lock_policy_set('owner_closed_period_mode', '"reason"'::jsonb, 'test reason mode') is not null as rs1 \gset
select tt.err('B4 owner without a window is refused with a clear code', format($$select cash_move_add(1,'owner_topup',31,%L::date,'cash',null,'t_b4',null,gen_random_uuid(),false)$$, :'dc'), 'period_closed_reason_required');
reset role; select tt.as(:'u_o');
select tt.err('B4 the refusal covers a direct entry dated in the closed month through the table trigger too', format($$insert into entries (form_code, location_id, entry_date, data, status) values ('10-2', 1, %L::date, '{}', 'draft')$$, :'dc'), 'period_closed_reason_required');
set role authenticated; select tt.as(:'u_o');
select tt.ok('B4 a date after the lock is still free for the owner', format($$select cash_move_add(1,'owner_topup',32,%L::date,'cash',null,'t_b4b',null,gen_random_uuid(),false)$$, :'d10'));
select (period_override_start('test: late paper bill of last month', :'dc'::date - 2, :'dc'::date + 2, 30) ->> 'id')::bigint as w1 \gset
select tt.as(:'u_o');
select count(*) as ex_before from money_exceptions where kind='period_lock_exception' \gset
select count(*) as al_before from audit_log where action='period_override_used' \gset
select tt.ok('B4 with the window the owner can date the cash move into the closed month', format($$select cash_move_add(1,'owner_topup',33,%L::date,'cash',null,'t_b4c',null,gen_random_uuid(),false)$$, :'dc'));
select tt.chk('B4 exactly one audit line "period_override_used" for that use', (select count(*) from audit_log where action='period_override_used') = :'al_before'::int + 1);
select tt.chk('B4 exactly one new line in the Exceptions list, open, with the reason', (select count(*) from money_exceptions where kind='period_lock_exception') = :'ex_before'::int + 1
  and (select reason from money_exceptions where kind='period_lock_exception' order by id desc limit 1) like 'test: late paper bill of last month%' and (select status from money_exceptions where kind='period_lock_exception' order by id desc limit 1)='open');
select tt.chk('B4 the window counts its use', (select uses from period_overrides where id=:'w1')=1);
select tt.err('B4 a date outside the window is refused', format($$select cash_move_add(1,'owner_topup',34,%L::date,'cash',null,'t_b4d',null,gen_random_uuid(),false)$$, :'d60'), 'period_closed_reason_required');
reset role;
update period_overrides set expires_at = now() - interval '1 minute' where id = :'w1';
set role authenticated; select tt.as(:'u_o');
select tt.err('B4 an expired window no longer helps', format($$select cash_move_add(1,'owner_topup',35,%L::date,'cash',null,'t_b4e',null,gen_random_uuid(),false)$$, :'dc'), 'period_closed_reason_required');
select (period_override_start('test: second window', :'dc'::date - 2, :'dc'::date + 2, 30) ->> 'id')::bigint as w2 \gset
select period_override_end(:'w2'::bigint, 'closed early') is not null as we2 \gset
select tt.err('B4 an ended window no longer helps', format($$select cash_move_add(1,'owner_topup',36,%L::date,'cash',null,'t_b4f',null,gen_random_uuid(),false)$$, :'dc'), 'period_closed_reason_required');
select (period_override_start('test: window for the accountant', :'dc'::date - 2, :'dc'::date + 2, 30, 'lock', :'u_acc'::uuid) ->> 'id')::bigint as w3 \gset
select tt.err('B4 a window for another person does not help the owner', format($$select cash_move_add(1,'owner_topup',37,%L::date,'cash',null,'t_b4g',null,gen_random_uuid(),false)$$, :'dc'), 'period_closed_reason_required');
select tt.as(:'u_acc');
select tt.ok('B4 the person named in the window can work in the closed month (non-owner, no old grant)', format($$select cash_move_add(1,'owner_topup',38,%L::date,'cash',null,'t_b4h',null,gen_random_uuid(),false)$$, :'dc'));
select tt.as(:'u_m1');
select tt.err('B4 another non-owner is still refused', format($$select cash_move_add(1,'owner_topup',39,%L::date,'cash',null,'t_b4i',null,gen_random_uuid(),false)$$, :'dc'), 'period_closed');
reset role; select tt.as(:'u_o');
set role authenticated; select tt.as(:'u_o');
select tt.chk('B4 the log lists them', jsonb_array_length(period_override_log() -> 'windows')>=3 and jsonb_array_length(period_override_log() -> 'exceptions')>=2 and jsonb_array_length(period_override_log() -> 'audit')>=3);
select tt.chk('B4 the state shows the open windows with the person', jsonb_array_length(period_lock_state() -> 'open_windows')>=1);

\echo == B5 a non-owner with the old closed_period_edit role grant keeps working (old rule intact)
reset role;
insert into rule_grants (grant_code, role_code) values ('closed_period_edit','showroom_manager') on conflict do nothing;
set role authenticated; select tt.as(:'u_m1');
select tt.ok('B5 role grant closed_period_edit still lets the manager through', format($$select cash_move_add(1,'owner_topup',41,%L::date,'cash',null,'t_b5',null,gen_random_uuid(),false)$$, :'dc'));
reset role;
delete from rule_grants where grant_code='closed_period_edit' and role_code='showroom_manager';

\echo == B6 modes: off, auto
set role authenticated; select tt.as(:'u_o');
select period_lock_policy_set('period_lock_mode', '"off"'::jsonb, 'test off') is not null as mo1 \gset
select tt.as(:'u_acc');
select tt.ok('B6 mode off: no lock for anyone (accountant)', format($$select cash_move_add(1,'owner_topup',51,%L::date,'cash',null,'t_b6',null,gen_random_uuid(),false)$$, :'dc'));
select tt.as(:'u_o');
select tt.ok('B6 mode off: no lock for the owner either, even with the reason mode', format($$select cash_move_add(1,'owner_topup',52,%L::date,'cash',null,'t_b6b',null,gen_random_uuid(),false)$$, :'dc'));
select period_lock_policy_set('auto_lock_day', '10'::jsonb, 'test day') is not null as ad3 \gset
select period_lock_policy_set('period_lock_mode', '"auto"'::jsonb, 'test auto') is not null as mo2 \gset
reset role;
select _w1b_auto_date(tt.today(), 10) as auto_d \gset
select (:'auto_d'::date - 3) as in_auto \gset
select (:'auto_d'::date + 1) as after_auto \gset
set role authenticated; select tt.as(:'u_o');
select tt.chk('B6 auto: the state shows the later of both dates', (period_lock_state() ->> 'effective_lock_date')::date = greatest(:'ld'::date, :'auto_d'::date));
select tt.as(:'u_acc');
select tt.err('B6 auto: a date inside the automatically closed month is refused for the accountant', format($$select cash_move_add(1,'owner_topup',53,%L::date,'cash',null,'t_b6c',null,gen_random_uuid(),false)$$, :'in_auto'), 'period_closed');
select tt.ok('B6 auto: the first day after it is free', format($$select cash_move_add(1,'owner_topup',54,%L::date,'cash',null,'t_b6d',null,gen_random_uuid(),false)$$, :'after_auto'));
select tt.as(:'u_o');
select tt.err('B6 auto: the owner is refused without a window in the reason mode', format($$select cash_move_add(1,'owner_topup',55,%L::date,'cash',null,'t_b6e',null,gen_random_uuid(),false)$$, :'in_auto'), 'period_closed_reason_required');
select period_lock_policy_set('period_lock_mode', '"manual"'::jsonb, 'test manual') is not null as mo3 \gset
select period_lock_policy_set('auto_lock_day', null, 'cleared') is not null as ad4 \gset
select tt.chk('B6 back to manual: the typed date', (period_lock_state() ->> 'effective_lock_date')::date = :'ld'::date);

\echo == B7 posting follows the date, not the person (accounting on, owner mode reason)
reset role; select tt.as(:'u_o');
select acct_set_start((:'dc'::date - 20)) is not null as ast \gset
select set_rule('accounting_on','true') is null as on1 \gset
set role authenticated; select tt.as(:'u_acc');
select acct_post_pending(true) ->> 'locked' as lk_acc \gset
select tt.as(:'u_o');
select acct_post_pending(true) ->> 'locked' as lk_own \gset
select tt.chk('B7 the dry run skips the same documents for the owner and the accountant (owner mode reason)', :'lk_acc'::int > 0 and :'lk_acc' = :'lk_own');
reset role; select tt.as(:'u_o');
update rules set value = '"off"' where key = 'owner_closed_period_mode';
set role authenticated; select tt.as(:'u_o');
select acct_post_pending(true) ->> 'locked' as lk_own_off \gset
select tt.chk('B7 with the owner mode off the owner''s run is the old one (nothing skipped for him)', :'lk_own_off'::int = 0);
reset role; select tt.as(:'u_o');
update rules set value = '"reason"' where key = 'owner_closed_period_mode';
select tt.chk('B7 the books stay balanced', tt.unbalanced()=0);

\echo == B8 back-date window per document type (cash move, quick expense, purchase, production)
reset role; select tt.as(:'u_o');
update rules set value = '"off"' where key = 'period_lock_mode';       -- keep the lock out of the way for this block
set role authenticated; select tt.as(:'u_o');
select period_lock_policy_set('backdate_max_days_cash_move', '7'::jsonb, 'test limit') is not null as bd1 \gset
select tt.ok('B8 cash move 5 days back is inside the limit', format($$select cash_move_add(1,'owner_topup',61,%L::date,'cash',null,'t_b8',null,gen_random_uuid(),false)$$, :'d5'));
select tt.err('B8 cash move 10 days back is refused for the owner too', format($$select cash_move_add(1,'owner_topup',62,%L::date,'cash',null,'t_b8b',null,gen_random_uuid(),false)$$, :'d10'), 'backdate_over_limit');
select tt.err('B8 the dry run tells the same', format($$select cash_move_add(1,'owner_topup',62,%L::date,'cash',null,'t_b8b',null,null,true)$$, :'d10'), 'backdate_over_limit');
select tt.err('B8 a cash move dated in the year 2000 is refused', $$select cash_move_add(1,'owner_topup',63,date '2000-01-02','cash',null,'t_b8c',null,gen_random_uuid(),false)$$, 'backdate_over_limit');
select (period_override_start('test: month-end cash move', :'d10'::date, :'d10'::date, 30, 'backdate', null, 'cash_move') ->> 'id')::bigint as wb1 \gset
select count(*) as bx_before from money_exceptions where kind='backdate_exception' \gset
select tt.ok('B8 a back-date window for that document type lets the owner through', format($$select cash_move_add(1,'owner_topup',64,%L::date,'cash',null,'t_b8d',null,gen_random_uuid(),false)$$, :'d10'));
select tt.chk('B8 one backdate_exception line with the reason and one audit line', (select count(*) from money_exceptions where kind='backdate_exception') = :'bx_before'::int + 1
  and (select reason from money_exceptions where kind='backdate_exception' order by id desc limit 1) like 'test: month-end cash move%');
select period_lock_policy_set('backdate_max_days_expense', '3'::jsonb, 'test limit') is not null as bd2 \gset
select tt.err('B8 quick expense 5 days back is refused (limit 3)', format($$select quick_expense_add(1,%L::date,'transport','test_rider',50,'cash',false,null,gen_random_uuid())$$, :'d5'), 'backdate_over_limit');
select tt.ok('B8 quick expense 3 days back is inside the limit', format($$select quick_expense_add(1,%L::date,'transport','test_rider',51,'cash',false,null,gen_random_uuid())$$, :'d3'));
select period_lock_policy_set('backdate_max_days_purchase', '30'::jsonb, 'test limit') is not null as bd3 \gset
select tt.err('B8 purchase bill 60 days back is refused (limit 30)', format($$select save_purchase(gen_random_uuid(),null,%L::uuid,1,'B8-1',%L::date,'[{"description":"x","qty":1,"unit_cost":5}]'::jsonb)$$, :'sup', :'d60'), 'backdate_over_limit');
select tt.ok('B8 purchase bill 20 days back is inside the limit', format($$select save_purchase(gen_random_uuid(),null,%L::uuid,1,'B8-2',%L::date,'[{"description":"x","qty":1,"unit_cost":5}]'::jsonb)$$, :'sup', :'d20'));
reset role; select tt.as(:'u_o');
select save_purchase(null,null,:'sup'::uuid,1,'B8-3',:'d20'::date,'[{"description":"x","qty":1,"unit_cost":5}]'::jsonb) ->> 'id' as pb1 \gset
update rules set value = '10' where key = 'backdate_max_days_purchase';
set role authenticated; select tt.as(:'u_o');
select tt.ok('B8 editing a draft without changing its date passes even when the limit is now smaller', format($$select save_purchase(null,%L::uuid,%L::uuid,1,'B8-3',%L::date,'[{"description":"x","qty":2,"unit_cost":5}]'::jsonb)$$, :'pb1', :'sup', :'d20'));
select tt.err('B8 changing the draft date to an old date is refused', format($$select save_purchase(null,%L::uuid,%L::uuid,1,'B8-3',%L::date,'[{"description":"x","qty":2,"unit_cost":5}]'::jsonb)$$, :'pb1', :'sup', :'d60'), 'backdate_over_limit');
select period_lock_policy_set('backdate_max_days_production', '2'::jsonb, 'test limit') is not null as bd4 \gset
reset role; select tt.as(:'u_o');
select tt.err('B8 production helper: 5 days back is refused (limit 2)', format($$select _w1b_backdate_check('production', %L::date, null, 'production_runs')$$, :'d5'), 'backdate_over_limit');
select tt.ok('B8 production helper: today is fine', $$select _w1b_backdate_check('production', tt.today(), null, 'production_runs')$$);
select tt.chk('B8 production_post carries the hook', position('_w1b_backdate_check(''production''' in pg_get_functiondef('public.production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)'::regprocedure))>0);
update rules set value = null where key in ('backdate_max_days_purchase', 'backdate_max_days_production');
select tt.ok('B8 a blank limit is off for any date, and an unknown document type is ignored', $$select _w1b_backdate_check('purchase', date '2000-01-02', null, null), _w1b_backdate_check('production', date '2000-01-02', null, null), _w1b_backdate_check('nothing', date '2000-01-02', null, null)$$);
select tt.err('B8 no window is ever deleted', $$delete from period_overrides$$, 'nothing is deleted');

\echo == B9 back-date: a one-off owner grant (phase87), a role grant, the maker is not the owner
set role authenticated; select tt.as(:'u_o');
select tt.as(:'u_m1');
select tt.err('B9 the manager is refused over the limit', format($$select cash_move_add(1,'owner_topup',71,%L::date,'cash',null,'t_b9',null,gen_random_uuid(),false)$$, :'d10'), 'backdate_over_limit');
select tt.as(:'u_o');
select money_exception_grant('override', 'test: one-off back-date', :'u_m1'::uuid, null, 'backdate:cash_move', null, null, :'d10'::date) is not null as g1 \gset
select tt.as(:'u_m1');
select tt.ok('B9 with the one-off grant the manager can date it back once', format($$select cash_move_add(1,'owner_topup',72,%L::date,'cash',null,'t_b9b',null,gen_random_uuid(),false)$$, :'d10'));
select tt.err('B9 the grant is used up: a second one is refused', format($$select cash_move_add(1,'owner_topup',73,%L::date,'cash',null,'t_b9c',null,gen_random_uuid(),false)$$, :'d10'), 'backdate_over_limit');
reset role;
insert into rule_grants (grant_code, role_code) values ('backdate_over_limit','showroom_manager') on conflict do nothing;
select count(*) as bx2 from money_exceptions where kind='backdate_exception' \gset
set role authenticated; select tt.as(:'u_m1');
select tt.ok('B9 a role the owner trusts with backdate_over_limit may go over', format($$select cash_move_add(1,'owner_topup',74,%L::date,'cash',null,'t_b9d',null,gen_random_uuid(),false)$$, :'d10'));
reset role;
select tt.chk('B9 and that is on the Exceptions list and in audit_log', (select count(*) from money_exceptions where kind='backdate_exception') = :'bx2'::int + 1 and tt.aln('backdate_over_limit')>=1);
delete from rule_grants where grant_code='backdate_over_limit' and role_code='showroom_manager';
set role authenticated; select tt.as(:'u_acc');
select tt.err('B9 the accountant without any of these is refused', format($$select cash_move_add(1,'owner_topup',75,%L::date,'cash',null,'t_b9e',null,gen_random_uuid(),false)$$, :'d10'), 'backdate_over_limit');
reset role; select tt.as(:'u_o');
update rules set value = null where key in ('backdate_max_days_cash_move', 'backdate_max_days_expense');
set role authenticated; select tt.as(:'u_o');
select gen_random_uuid() as dupc \gset
select cash_move_add(1,'owner_topup',76,:'d60'::date,'cash',null,'t_b9f',null,:'dupc'::uuid,false) is not null as dp1 \gset
select period_lock_policy_set('backdate_max_days_cash_move', '7'::jsonb, 'again') is not null as bd5 \gset
select tt.chk('B9 the same client id sent again after the limit was set answers duplicate', (cash_move_add(1,'owner_topup',76,:'d60'::date,'cash',null,'t_b9f',null,:'dupc'::uuid,false) ->> 'dup')::boolean);
select period_lock_policy_set('backdate_max_days_cash_move', null, 'cleared') is not null as bd6 \gset

\echo == B10 late offline sale: redate_flag, then park, accept, redate, reject, maker and decider
set role authenticated; select tt.as(:'u_o');
select period_lock_policy_set('late_sale_policy', '"redate_flag"'::jsonb, 'test flag') is not null as lp1 \gset
select tt.as(:'u_st');
select record_sale2(gen_random_uuid(),1,'[{"amount":800}]',0,'[{"mode":"cash","amount":800}]',null,null,'retail',null,true, now() - interval '90 hours') ->> 'id' as s90 \gset
select tt.chk('B10 redate_flag: re-dated as before', (select abs(extract(epoch from now() - sold_at)) < 30 from sales where id=:'s90'::uuid));
reset role;
select tt.chk('B10 redate_flag: one line in the Exceptions list and one audit line', tt.exn('late_sale_redated')=1 and tt.aln('late_sale_redated')=1
  and (select src_id from money_exceptions where kind='late_sale_redated')=:'s90');
set role authenticated; select tt.as(:'u_o');
select period_lock_policy_set('late_sale_policy', '"park"'::jsonb, 'test park') is not null as lp2 \gset
select tt.as(:'u_st');
select gen_random_uuid() as c1 \gset
select record_sale2(:'c1'::uuid,1,'[{"amount":900}]',0,'[{"mode":"cash","amount":900}]',null,null,'retail',null,true, now() - interval '80 hours') as r1 \gset
select tt.chk('B10 park: the answer says parked, with a held id, and no sale exists', (:'r1'::jsonb ->> 'parked')::boolean and (:'r1'::jsonb ->> 'held_id') is not null);
reset role;
select tt.chk('B10 park: nothing in sales for that client id, one held row, one open late_sale_held line, one audit line', (select count(*) from sales where client_id=:'c1'::uuid)=0
  and (select count(*) from late_sales_held where client_id=:'c1'::uuid and status='held')=1 and tt.exn('late_sale_held')=1 and tt.aln('late_sale_held')=1);
set role authenticated; select tt.as(:'u_st');
select tt.chk('B10 park: sending the same client id again answers the same held row', (record_sale2(:'c1'::uuid,1,'[{"amount":900}]',0,'[{"mode":"cash","amount":900}]',null,null,'retail',null,true, now() - interval '80 hours') ->> 'dup')::boolean);
select tt.chk('B10 park: the cashier cannot read the held rows (owner side only)', (select count(*) from late_sales_held)=0);
reset role;
select tt.chk('B10 park: still exactly one held row for that client id', (select count(*) from late_sales_held where client_id=:'c1'::uuid)=1);
set role authenticated; select tt.as(:'u_st');
select record_sale2(gen_random_uuid(),1,'[{"amount":910}]',0,'[{"mode":"cash","amount":910}]',null,null,'retail',null,true, now() - interval '60 hours') ->> 'id' as s60p \gset
select tt.chk('B10 park: a sale inside the offline limit is not held (keeps its own time)', (select abs(extract(epoch from (now() - interval '60 hours') - sold_at)) < 30 from sales where id=:'s60p'::uuid));
select tt.err('B10 the cashier cannot decide his own held sale (no permission)', format($$select late_sale_release(%s,'accept','test reason')$$, (:'r1'::jsonb ->> 'held_id')), 'not allowed');
select tt.as(:'u_o');
select tt.err('B10 a reason is needed', format($$select late_sale_release(%s,'accept','')$$, (:'r1'::jsonb ->> 'held_id')), 'reason_required');
select tt.err('B10 an unknown action is refused', format($$select late_sale_release(%s,'approve','test reason')$$, (:'r1'::jsonb ->> 'held_id')), 'bad_action');
select tt.err('B10 an unknown held sale is refused', $$select late_sale_release(999999,'accept','test reason')$$, 'not found');
select tt.chk('B10 the owner sees the held sale in the list', jsonb_array_length(late_sales_held_list('held'))=1 and (late_sales_held_list('held') -> 0 ->> 'n_lines')::int=1);
select late_sale_release((:'r1'::jsonb ->> 'held_id')::bigint, 'accept', 'test: seen on the paper sheet') as rel1 \gset
reset role;
select tt.chk('B10 accept: the sale exists, made by the cashier, with its OWN time', (select count(*) from sales where client_id=:'c1'::uuid and created_by=:'u_st'::uuid)=1
  and (select abs(extract(epoch from (now() - interval '80 hours') - sold_at)) < 120 from sales where client_id=:'c1'::uuid) and (select sale_date from sales where client_id=:'c1'::uuid) < tt.today());
select tt.chk('B10 accept: held row accepted with the reason, the Exceptions line resolved, audit line written', (select status from late_sales_held where client_id=:'c1'::uuid)='accepted'
  and (select decide_reason from late_sales_held where client_id=:'c1'::uuid) like 'test: seen%' and (select status from money_exceptions where id=(select exception_id from late_sales_held where client_id=:'c1'::uuid))='resolved' and tt.aln('late_sale_release')=1);
select tt.chk('B10 accept: the payment row carries the sale time and the cashier', (select count(*) from sale_payments p join sales s on s.id=p.sale_id where s.client_id=:'c1'::uuid and p.created_by=:'u_st'::uuid)=1);
select tt.chk('B10 the identity was restored after the release (the claim is the owner again)', current_setting('request.jwt.claim.sub')=:'u_o');
set role authenticated; select tt.as(:'u_o');
select tt.err('B10 a decided held sale cannot be decided twice', format($$select late_sale_release(%s,'reject','test reason')$$, (:'r1'::jsonb ->> 'held_id')), 'already_decided');
select tt.as(:'u_st');
select gen_random_uuid() as c2 \gset
select (record_sale2(:'c2'::uuid,1,'[{"amount":920}]',0,'[{"mode":"cash","amount":920}]',null,null,'retail',null,true, now() - interval '100 hours') ->> 'held_id')::bigint as h2 \gset
select gen_random_uuid() as c3 \gset
select (record_sale2(:'c3'::uuid,1,'[{"amount":930}]',0,'[{"mode":"cash","amount":930}]',null,null,'retail',null,true, now() - interval '110 hours') ->> 'held_id')::bigint as h3 \gset
select tt.as(:'u_o');
select late_sale_release(:'h2'::bigint, 'redate', 'test: take today') is not null as rel2 \gset
select late_sale_release(:'h3'::bigint, 'reject', 'test: duplicate of a sheet') is not null as rel3 \gset
reset role;
select tt.chk('B10 redate: the sale exists with the time of now', (select abs(extract(epoch from now() - sold_at)) < 60 from sales where client_id=:'c2'::uuid) and (select status from late_sales_held where id=:'h2')='redated');
select tt.chk('B10 reject: no sale is recorded, the row is rejected with the reason, nothing is deleted', (select count(*) from sales where client_id=:'c3'::uuid)=0 and (select status from late_sales_held where id=:'h3')='rejected'
  and (select count(*) from late_sales_held)=3);
select tt.chk('B10 the totals: three held sales, none left open', (select count(*) from late_sales_held where status='held')=0 and (period_lock_state() ->> 'held_sales')::int=0);

\echo == B11 maker and decider: the owner makes a late sale himself
set role authenticated; select tt.as(:'u_o');
select (record_sale2(gen_random_uuid(),1,'[{"amount":940}]',0,'[{"mode":"cash","amount":940}]',null,null,'retail',null,true, now() - interval '100 hours') ->> 'held_id')::bigint as h4 \gset
reset role;
update rules set value = 'false' where key = 'owner_self_approve';
set role authenticated; select tt.as(:'u_o');
select tt.err('B11 the maker cannot decide his own request (owner_self_approve off)', format($$select late_sale_release(%s,'accept','test reason')$$, :'h4'), 'maker_cannot_decide');
reset role;
update rules set value = 'true' where key = 'owner_self_approve';
set role authenticated; select tt.as(:'u_o');
select tt.ok('B11 with owner_self_approve on the owner may decide his own', format($$select late_sale_release(%s,'accept','test reason')$$, :'h4'));
reset role; select tt.as(:'u_o');
update rules set value = null where key = 'owner_self_approve';
select tt.chk('B11 the owner-made sale was recorded as the owner', (select count(*) from sales where created_by=:'u_o'::uuid and sold_at < now() - interval '90 hours')=1);
select tt.chk('B11 the book is balanced', tt.unbalanced()=0);

\echo == B12 a held sale released into a month that is closed meanwhile: the lock applies as the cashier
set role authenticated; select tt.as(:'u_st2');
select (record_sale2(gen_random_uuid(),1,'[{"amount":950}]',0,'[{"mode":"cash","amount":950}]',null,null,'retail',null,true, now() - interval '100 hours') ->> 'held_id')::bigint as h5 \gset
reset role; select tt.as(:'u_o');
update rules set value = '"manual"' where key = 'period_lock_mode';
update rules set value = to_jsonb(tt.today()::text) where key = 'period_closed_until';
set role authenticated; select tt.as(:'u_o');
select tt.err('B12 accept into a closed month is refused (the cashier has no window)', format($$select late_sale_release(%s,'accept','test reason')$$, :'h5'), 'period_closed');
select tt.chk('B12 and nothing was half done: the held row is still held', (select status from late_sales_held where id=:'h5')='held');
select (period_override_start('test: release a held sale into the closed month', tt.today() - 10, tt.today(), 30, 'lock', :'u_st2'::uuid) ->> 'id')::bigint as w5 \gset
select tt.ok('B12 with a window for the cashier named in it the owner can accept', format($$select late_sale_release(%s,'accept','test reason')$$, :'h5'));
select period_lock_set(:'ld'::date, 'test: back to the old date') is not null as lk0 \gset

\echo == B13 guards on rules: lock date backward, accounting start date after an opening, accounting ON after OFF, auto mode without a day
set role authenticated; select tt.as(:'u_o');
select tt.ok('B13 policy allow (default): the lock date moves back with a plain set_rule', format($$select set_rule('period_closed_until', to_jsonb(%L::text))$$, (:'ld'::date - 5)::text));
select period_lock_policy_set('lock_backward_policy', '"reason_always"'::jsonb, 'test') is not null as lb1 \gset
select tt.err('B13 reason_always: a plain set_rule back is refused', format($$select set_rule('period_closed_until', to_jsonb(%L::text))$$, (:'ld'::date - 20)::text), 'lock_backward_needs_reason');
select tt.err('B13 reason_always: the screen function needs a reason too', format($$select period_lock_set(%L::date, '')$$, (:'ld'::date - 20)), 'reason_required');
select tt.ok('B13 moving forward needs no reason', format($$select period_lock_set(%L::date, null)$$, :'ld'::date));
select count(*) as lx from money_exceptions where kind='period_lock_exception' \gset
select tt.ok('B13 moving back with a reopen reason works', format($$select period_lock_set(%L::date, 'test: wrong month was closed')$$, (:'ld'::date - 20)));
select tt.chk('B13 and leaves an Exceptions line and an audit line', (select count(*) from money_exceptions where kind='period_lock_exception') = :'lx'::int + 1 and exists (select 1 from audit_log where action='period_lock_set' and detail ->> 'reason'='test: wrong month was closed'));
select period_lock_policy_set('lock_backward_policy', '"reason_after_year_close"'::jsonb, 'test') is not null as lb2 \gset
select tt.ok('B13 reason_after_year_close, no year closed: moving back needs no reason', format($$select set_rule('period_closed_until', to_jsonb(%L::text))$$, (:'ld'::date - 30)::text));
reset role;
insert into year_closes (fiscal_from, fiscal_to, status) values (:'ld'::date - 300, :'ld'::date - 25, 'closed');
set role authenticated; select tt.as(:'u_o');
select tt.ok('B13 forward again', format($$select set_rule('period_closed_until', to_jsonb(%L::text))$$, (:'ld'::date)::text));
select tt.err('B13 a year is closed: moving the date back into it needs a reason', format($$select set_rule('period_closed_until', to_jsonb(%L::text))$$, (:'ld'::date - 40)::text), 'lock_backward_needs_reason');
select tt.ok('B13 moving back to a date AFTER the closed year needs none', format($$select set_rule('period_closed_until', to_jsonb(%L::text))$$, (:'ld'::date - 10)::text));
select tt.ok('B13 the screen function with a reopen reason moves it into the closed year', format($$select period_lock_set(%L::date, 'test: reopen the year')$$, (:'ld'::date - 40)));
select period_lock_policy_set('lock_backward_policy', '"allow"'::jsonb, 'test') is not null as lb3 \gset
select period_lock_set(:'ld'::date, 'forward') is not null as lk1 \gset

reset role; select tt.as(:'u_o');
select _acct_write(tt.today(), 1, 'opening', 'test89', null, 'test opening', null, _acct_resolve('[{"code":"1110","debit":10},{"code":"3100","credit":10}]'::jsonb, 1)) is not null as op1 \gset
select rule_txt('accounting_start_date') as sd0 \gset
set role authenticated; select tt.as(:'u_o');
select tt.ok('B13 start date after an opening, switch OFF (default): can still move, as today', format($$select set_rule('accounting_start_date', to_jsonb(%L::text))$$, (:'dc'::date - 21)::text));
select period_lock_policy_set('start_date_lock_after_opening', 'true'::jsonb, 'test') is not null as sl1 \gset
select tt.err('B13 switch ON: the start date cannot move after an opening exists', format($$select set_rule('accounting_start_date', to_jsonb(%L::text))$$, (:'dc'::date - 22)::text), 'start_date_locked_by_opening');
select tt.err('B13 and acct_set_start goes through the same guard', format($$select acct_set_start(%L::date)$$, (:'dc'::date - 23)), 'start_date_locked_by_opening');
select period_lock_policy_set('start_date_lock_after_opening', 'false'::jsonb, 'test') is not null as sl2 \gset

select period_lock_policy_set('accounting_on_needs_reason', 'true'::jsonb, 'test') is not null as ar1 \gset
select tt.ok('B13 switching accounting OFF needs no reason', $$select set_rule('accounting_on', 'false'::jsonb)$$);
select tt.err('B13 switching it ON by set_rule is refused', $$select set_rule('accounting_on', 'true'::jsonb)$$, 'accounting_on_needs_reason');
select tt.err('B13 accounting_on_set without a reason is refused', $$select accounting_on_set(true, '')$$, 'reason_required');
select tt.chk('B13 the backlog preview shows what would be posted', (accounting_on_preview() ->> 'ran')::boolean and (accounting_on_preview() ->> 'would_post')::int >= 0 and accounting_on_preview() ? 'by_type');
select accounting_on_set(true, 'test: back on after the bank file was fixed') as aon \gset
select tt.chk('B13 with the reason it is ON again, the audit line has the reason and the backlog', rule_on('accounting_on') and exists (select 1 from audit_log where action='accounting_on_set' and detail ->> 'reason' like 'test: back on%' and detail ? 'backlog'));
select tt.chk('B13 the flag does not leak: a later plain switch ON is refused again', (select true from (select set_rule('accounting_on','false'::jsonb)) z) is true);
select tt.err('B13 plain ON refused again', $$select set_rule('accounting_on', 'true'::jsonb)$$, 'accounting_on_needs_reason');
select accounting_on_set(true, 'test: on again') is not null as aon2 \gset
select period_lock_policy_set('accounting_on_needs_reason', 'false'::jsonb, 'test') is not null as ar2 \gset

\echo == B14 sale / purchase / cash move paths still post balanced entries after all of this
reset role; select tt.as(:'u_o');
select acct_post_pending(false) is not null as pp \gset
select tt.chk('B14 the journal is balanced', tt.unbalanced()=0);

\echo == B15 lateness report and state
set role authenticated; select tt.as(:'u_o');
select tt.chk('B15 the lateness report lists the document types with records', (period_lateness_report(30) -> 'by_document') ? 'cash_move' and (period_lateness_report(30) -> 'by_document' -> 'cash_move' ->> 'records')::int > 0);
select tt.chk('B15 the state is complete for the screen', period_lock_state() ?& array['mode','manual_date','auto_day','effective_lock_date','owner_mode','backdate','late_sale_policy','offline_hours','hooks','my_windows','open_windows']);
reset role;
select tt.ok('B15 lock_check with a null date does nothing', $$select public.lock_check(null)$$);
select tt.err('B15 a held sale is never deleted', $$delete from late_sales_held$$, 'nothing is deleted');
select tt.chk('B15 the grant catalog has the two new grants', (select count(*) from grant_defs where grant_code in ('late_sale_release','backdate_over_limit'))=2);

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
